#include "platform/Platform.h"
#include "platform/Common.h"
#include "core/Segmenter.h"

namespace cm {

static NSDictionary* httpJSON(NSString* url, NSDictionary* headers, NSDictionary* body, std::string* err) {
    NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 180;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    for (NSString* k in headers) [req setValue:headers[k] forHTTPHeaderField:k];
    NSError* e = nil;
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:&e];
    if (!req.HTTPBody) { if (err) *err = str(e.localizedDescription); return nil; }

    __block NSData* data = nil; __block NSError* nerr = nil; __block NSInteger code = 0;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionDataTask* task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData* d, NSURLResponse* r, NSError* ee) {
            data = d; nerr = ee; code = [(NSHTTPURLResponse*)r statusCode]; dispatch_semaphore_signal(sem);
        }];
    [task resume];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (nerr) { if (err) *err = str(nerr.localizedDescription); return nil; }
    NSDictionary* j = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (code < 200 || code >= 300) {
        NSString* msg = j[@"error"][@"message"] ?: j[@"error"] ?: [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (err) *err = "HTTP " + std::to_string(code) + ": " + str([msg description]);
        return nil;
    }
    if (![j isKindOfClass:NSDictionary.class]) { if (err) *err = "Non-JSON response"; return nil; }
    return j;
}

static std::string callLLM(const Settings& s, const std::string& system, const std::string& user, std::string* err) {
    std::string model = s.model;
    NSDictionary* j = nil;
    switch (s.provider) {
    case Settings::Anthropic: {
        if (s.apiKey.empty()) { if (err) *err = "Anthropic API key missing"; return ""; }
        if (model.empty()) model = "claude-sonnet-5-5";
        std::string base = s.baseURL.empty() ? "https://api.anthropic.com" : s.baseURL;
        j = httpJSON(ns(base + "/v1/messages"),
                     @{@"x-api-key": ns(s.apiKey), @"anthropic-version": @"2023-06-01"},
                     @{@"model": ns(model), @"max_tokens": @4096, @"temperature": @0.3, @"system": ns(system),
                       @"messages": @[@{@"role": @"user", @"content": ns(user)}]}, err);
        if (!j) return "";
        NSMutableString* out = [NSMutableString string];
        for (NSDictionary* c in j[@"content"]) if ([c[@"type"] isEqualToString:@"text"]) [out appendString:c[@"text"]];
        return str(out);
    }
    case Settings::Ollama: {
        if (model.empty()) model = "llama3.1";
        std::string base = s.baseURL.empty() ? "http://localhost:11434" : s.baseURL;
        j = httpJSON(ns(base + "/api/chat"), @{},
                     @{@"model": ns(model), @"stream": @NO, @"format": @"json", @"options": @{@"temperature": @0.3},
                       @"messages": @[@{@"role": @"system", @"content": ns(system)}, @{@"role": @"user", @"content": ns(user)}]}, err);
        return j ? str(j[@"message"][@"content"]) : "";
    }
    case Settings::OpenAICompat: {
        if (model.empty()) model = "gpt-4o-mini";
        std::string base = s.baseURL.empty() ? "https://api.openai.com/v1" : s.baseURL;
        NSMutableDictionary* h = [NSMutableDictionary dictionary];
        if (!s.apiKey.empty()) h[@"Authorization"] = ns("Bearer " + s.apiKey);
        j = httpJSON(ns(base + "/chat/completions"), h,
                     @{@"model": ns(model), @"temperature": @0.3,
                       @"messages": @[@{@"role": @"system", @"content": ns(system)}, @{@"role": @"user", @"content": ns(user)}]}, err);
        return j ? str(j[@"choices"][0][@"message"][@"content"]) : "";
    }
    default: return "";
    }
}

std::vector<Candidate> aiSelectSegments(const Settings& s, const std::vector<Transcript>& transcripts,
                                        const std::vector<MediaInfo>& media, const std::vector<std::string>& imageVisuals,
                                        const std::string& idea, Script& script, std::string* err) {
    std::vector<Candidate> out;
    @autoreleasepool {
        std::string text = callLLM(s, buildSystemPrompt(), buildUserPrompt(transcripts, media, imageVisuals, idea, s), err);
        if (text.empty()) { if (err && err->empty()) *err = "Empty model response"; return out; }
        size_t a = text.find('{'), b = text.rfind('}');
        if (a == std::string::npos || b == std::string::npos || b <= a) { if (err) *err = "Model did not return JSON"; return out; }
        NSData* d = [ns(text.substr(a, b - a + 1)) dataUsingEncoding:NSUTF8StringEncoding];
        NSError* e = nil;
        NSDictionary* j = [NSJSONSerialization JSONObjectWithData:d options:0 error:&e];
        if (![j isKindOfClass:NSDictionary.class]) { if (err) *err = "Bad JSON: " + str(e.localizedDescription); return out; }
        auto S = [](id v) { return (v && v != NSNull.null) ? str([v description]) : std::string(); };
        script.title = S(j[@"title"]); script.description = S(j[@"description"]); script.narrative = S(j[@"script"]);
        script.hashtags.clear();
        if ([j[@"hashtags"] isKindOfClass:NSArray.class]) for (id h in j[@"hashtags"]) script.hashtags.push_back(S(h));
        for (NSDictionary* c in j[@"clips"]) {
            if (![c isKindOfClass:NSDictionary.class]) continue;
            Candidate k;
            k.sourceIndex = [c[@"source"] intValue];
            k.isImage = (S(c[@"type"]) == "image") || (k.sourceIndex >= 0 && k.sourceIndex < (int)media.size() && media[k.sourceIndex].isImage);
            k.start = [c[@"start"] doubleValue]; k.end = [c[@"end"] doubleValue];
            if (k.isImage) { k.start = 0; k.end = c[@"duration"] ? [c[@"duration"] doubleValue] : s.slideDuration; }
            k.score = c[@"score"] ? [c[@"score"] doubleValue] : 70;
            k.hook = S(c[@"hook"]); k.reason = S(c[@"reason"]); k.overlay = S(c[@"overlay"]);
            out.push_back(k);
        }
        if (out.empty() && err) *err = "Model returned no clips";
    }
    return out;
}

} // namespace cm
