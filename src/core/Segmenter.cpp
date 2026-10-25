#include "core/Segmenter.h"
#include <algorithm>
#include <cmath>
#include <set>
#include <sstream>
#include <cstdio>
#include <iomanip>

namespace cm {

static const std::set<std::string> kStop = {
    "the","a","an","and","or","of","to","in","on","for","with","is","are","was","were","be",
    "this","that","it","as","at","by","from","about","how","what","why","i","you","we","they",
    "my","your","our","me","us","them","so","but","if","then","than","can","will","just","like",
    "make","video","short","clip","clips","shorts","want","show","find","moments","moment","best"};

static std::vector<std::string> tokens(const std::string& s) {
    std::vector<std::string> out; std::string cur;
    for (char ch : lower(s)) {
        if (isalnum((unsigned char)ch) || ch == '\'') cur += ch;
        else if (!cur.empty()) { out.push_back(cur); cur.clear(); }
    }
    if (!cur.empty()) out.push_back(cur);
    return out;
}

static std::string stem(std::string w) {
    for (const char* suf : {"ing", "edly", "ed", "es", "s", "ly"}) {
        size_t n = strlen(suf);
        if (w.size() > n + 3 && w.compare(w.size() - n, n, suf) == 0) { w.erase(w.size() - n); break; }
    }
    return w;
}

std::vector<Candidate> heuristicCandidates(const std::vector<Transcript>& transcripts,
                                           const std::vector<MediaInfo>& media,
                                           const std::string& idea, const Settings& s) {
    std::set<std::string> keys;
    for (auto& t : tokens(idea)) if (!kStop.count(t) && t.size() > 2) keys.insert(stem(t));

    static const char* hooks[] = {"secret","never","always","mistake","why","how","best","worst","actually",
        "truth","nobody","everyone","first","biggest","stop","before","after","result","trick","hack",
        "important","key","remember","warning","problem","solution","free","money","fast","easy","simple"};

    std::vector<Candidate> out;
    for (size_t si = 0; si < transcripts.size(); ++si) {
        if (si < media.size() && media[si].isImage) continue;
        auto& tr = transcripts[si];
        auto& S = tr.sentences;
        for (size_t i = 0; i < S.size(); ++i) {
            double start = S[i].start, hits = 0, hookHits = 0, nWords = 0;
            for (size_t j = i; j < S.size(); ++j) {
                double end = S[j].end;
                for (auto& w : S[j].words) {
                    std::string t = stem(lower(w.text));
                    t.erase(std::remove_if(t.begin(), t.end(), [](char c){ return !isalnum((unsigned char)c); }), t.end());
                    nWords++;
                    if (keys.count(t)) hits++;
                    for (auto h : hooks) if (t == h) hookHits++;
                }
                double dur = end - start;
                if (dur < s.minClip) continue;
                if (dur > s.maxClip) break;
                double density = nWords > 0 ? hits / nWords : 0;
                double speech = nWords / std::max(1.0, dur);            // words per second
                double pace = std::exp(-0.5 * std::pow((speech - 2.6) / 1.2, 2)); // prefer natural pace
                bool questionStart = S[i].text.find('?') != std::string::npos;
                double sc = 100.0 * (0.55 * std::min(1.0, density * 6) + 0.2 * std::min(1.0, hookHits / 2.0)
                          + 0.15 * pace + (questionStart ? 0.1 : 0.0));
                if (keys.empty()) sc = 100.0 * (0.5 * std::min(1.0, hookHits / 2.0) + 0.5 * pace);
                Candidate c; c.sourceIndex = (int)si; c.start = start; c.end = end; c.score = sc;
                c.text = tr.textBetween(start, end);
                c.reason = keys.empty() ? "Natural pace, strong wording" : "Matches idea keywords";
                // hook = first 6 words
                std::istringstream is(c.text); std::string w; int n = 0;
                while (is >> w && n++ < 6) c.hook += (c.hook.empty() ? "" : " ") + w;
                out.push_back(c);
            }
        }
    }
    std::sort(out.begin(), out.end(), [](auto& a, auto& b){ return a.score > b.score; });
    // keep non-overlapping top candidates
    std::vector<Candidate> keep;
    for (auto& c : out) {
        bool ov = false;
        for (auto& k : keep) if (k.sourceIndex == c.sourceIndex && c.start < k.end + 1.0 && c.end > k.start - 1.0) { ov = true; break; }
        if (!ov) keep.push_back(c);
        if ((int)keep.size() >= std::max(8, s.maxClips * 3)) break;
    }
    // Still images become slides, interleaved after the video moments.
    std::vector<Candidate> withImages; size_t img = 0;
    std::vector<size_t> imgIdx; for (size_t i = 0; i < media.size(); ++i) if (media[i].isImage) imgIdx.push_back(i);
    for (size_t i = 0; i < keep.size() || img < imgIdx.size(); ++i) {
        if (i < keep.size()) withImages.push_back(keep[i]);
        if (img < imgIdx.size() && (i % 2 == 0 || i >= keep.size())) {
            Candidate c; c.sourceIndex = (int)imgIdx[img++]; c.isImage = true; c.start = 0; c.end = s.slideDuration;
            c.score = 50; c.reason = "Still image (slide)";
            std::string n = media[c.sourceIndex].path; n = n.substr(n.find_last_of('/') + 1);
            c.hook = n.substr(0, n.find_last_of('.'));
            withImages.push_back(c);
        }
    }
    return withImages;
}

std::string describeScript(const std::vector<Candidate>& c, const std::vector<MediaInfo>& media) {
    std::ostringstream o; int n = 0; double t = 0;
    for (auto& k : c) {
        if (!k.selected) continue;
        std::string name = media[k.sourceIndex].path; name = name.substr(name.find_last_of('/') + 1);
        o << ++n << ". [" << fmtTime(t) << "] " << (k.isImage ? "IMAGE " : "CLIP ") << name;
        if (!k.isImage) o << " " << fmtTime(k.start) << "-" << fmtTime(k.end);
        o << " (" << std::fixed << std::setprecision(1) << k.duration() << "s, score " << int(k.score) << ")\n";
        if (!k.hook.empty()) o << "   Title: " << k.hook << "\n";
        if (!k.overlay.empty()) o << "   On-screen text: " << k.overlay << "\n";
        if (!k.text.empty()) o << "   Says: \"" << k.text << "\"\n";
        if (!k.visual.empty()) o << "   Shows: " << k.visual << "\n";
        if (!k.reason.empty()) o << "   Why: " << k.reason << "\n";
        t += k.duration();
    }
    o << "\nTotal: " << std::setprecision(1) << t << " s";
    return o.str();
}

Script heuristicScript(const std::vector<Candidate>& c, const std::vector<MediaInfo>& media,
                       const std::string& idea, const Settings& s) {
    Script sc;
    sc.narrative = describeScript(c, media);
    std::string firstHook; std::string body;
    for (auto& k : c) if (k.selected && !k.isImage) { if (firstHook.empty()) firstHook = k.hook; if (body.size() < 400) body += k.text + " "; }
    sc.title = firstHook.empty() ? idea : firstHook;
    if (!sc.title.empty()) sc.title[0] = (char)toupper((unsigned char)sc.title[0]);
    sc.description = trim(body) + (idea.empty() ? "" : "\n\n" + idea);
    std::set<std::string> seen;
    for (auto& t : tokens(idea + " " + firstHook)) if (!kStop.count(t) && t.size() > 3 && seen.insert(t).second && sc.hashtags.size() < 8) sc.hashtags.push_back("#" + t);
    for (const char* h : {"#shorts", "#reels", "#tiktok"}) sc.hashtags.push_back(h);
    return sc;
}

std::string buildSystemPrompt() {
    return "You are an elite short-form video editor (TikTok/Reels/Shorts). You read transcripts with "
           "timestamps and pick the segments that best serve the creator's idea: strong hooks, complete "
           "thoughts, no mid-sentence starts, high retention. You answer with strict JSON only.";
}

std::string buildUserPrompt(const std::vector<Transcript>& transcripts, const std::vector<MediaInfo>& media,
                            const std::vector<std::string>& imageVisuals, const std::string& idea, const Settings& s) {
    std::ostringstream o;
    o << "IDEA / BRIEF:\n" << idea << "\n\n";
    o << "CONSTRAINTS:\n- Final video length: between " << int(s.minLength) << " and " << int(s.maxLength) << " seconds\n"
      << "- Use at most " << s.maxClips << " video segments, each " << int(s.minClip) << "-" << int(s.maxClip) << " seconds; "
      << "you may add a few extra lower-scored alternates\n"
      << "- Segments must start and end on sentence boundaries from the transcript\n"
      << "- List clips in the order they should play (strongest hook first)\n";
    bool anyImage = false; for (auto& m : media) anyImage |= m.isImage;
    if (anyImage) o << "- Still images are available; place each where it supports the narration (type \"image\", give it a duration of "
                    << int(s.slideDuration) << " s and short on-screen text)\n";
    o << "\nSOURCES:\n";
    for (size_t i = 0; i < media.size(); ++i) {
        std::string n = media[i].path; n = n.substr(n.find_last_of('/') + 1);
        if (media[i].isImage) o << "S" << i << " image " << n << " — shows: " << (i < imageVisuals.size() ? imageVisuals[i] : "") << "\n";
        else o << "S" << i << " video " << n << " (" << int(media[i].duration) << " s)\n";
    }
    o << "\nTRANSCRIPT (source, start-end seconds, text):\n";
    for (size_t si = 0; si < transcripts.size(); ++si)
        for (auto& st : transcripts[si].sentences) {
            char buf[64]; snprintf(buf, sizeof buf, "[S%zu %.2f-%.2f] ", si, st.start, st.end);
            o << buf << st.text << "\n";
        }
    o << "\nReturn ONLY JSON of the form:\n"
         "{\"title\":\"catchy post title\",\"description\":\"2-3 sentence post description with a call to action\","
         "\"hashtags\":[\"#tag1\",\"#tag2\"],"
         "\"script\":\"short editing rationale: pacing, why this order, what the viewer feels\","
         "\"clips\":[{\"type\":\"video\",\"source\":0,\"start\":12.34,\"end\":21.9,\"score\":87,"
         "\"hook\":\"<=6 word on-screen title\",\"overlay\":\"optional short text shown during the clip\",\"reason\":\"why it works\"},"
         "{\"type\":\"image\",\"source\":1,\"duration\":4,\"score\":60,\"overlay\":\"text over the image\",\"reason\":\"...\"}]}\n";
    return o.str();
}

void refineCandidates(std::vector<Candidate>& c, const std::vector<Transcript>& transcripts,
                      const std::vector<MediaInfo>& media, const Settings& s) {
    std::vector<Candidate> out;
    for (auto cand : c) {
        if (cand.sourceIndex < 0 || cand.sourceIndex >= (int)transcripts.size()) continue;
        if (media.size() > (size_t)cand.sourceIndex && media[cand.sourceIndex].isImage) {
            cand.isImage = true; cand.start = 0;
            if (cand.end <= 0) cand.end = s.slideDuration;
            cand.end = std::clamp(cand.end, 1.5, 12.0);
            if (cand.hook.empty() && cand.overlay.empty()) { std::string n = media[cand.sourceIndex].path; n = n.substr(n.find_last_of('/') + 1); cand.hook = n.substr(0, n.find_last_of('.')); }
            out.push_back(cand); continue;
        }
        auto& tr = transcripts[cand.sourceIndex];
        double dur = media.size() > (size_t)cand.sourceIndex ? media[cand.sourceIndex].duration : tr.duration;
        if (cand.end <= cand.start) continue;
        cand.start = tr.snapToWordBoundary(cand.start, true);
        cand.end = tr.snapToWordBoundary(cand.end, false);
        if (cand.end - cand.start > s.maxClip) cand.end = tr.snapToWordBoundary(cand.start + s.maxClip, false);
        if (cand.end - cand.start < s.minClip) cand.end = tr.snapToWordBoundary(cand.start + s.minClip, false);
        cand.start = std::max(0.0, cand.start);
        if (dur > 0) cand.end = std::min(dur, cand.end);
        if (cand.end - cand.start < 1.0) continue;
        if (cand.text.empty()) cand.text = tr.textBetween(cand.start, cand.end);
        if (cand.hook.empty()) {
            std::istringstream is(cand.text); std::string w; int n = 0;
            while (is >> w && n++ < 5) cand.hook += (cand.hook.empty() ? "" : " ") + w;
        }
        cand.score = std::clamp(cand.score, 0.0, 100.0);
        bool ov = false;
        for (auto& k : out) if (k.sourceIndex == cand.sourceIndex && cand.start < k.end && cand.end > k.start) { ov = true; break; }
        if (!ov) out.push_back(cand);
    }
    // keep the AI's play order; only the offline ranker is unordered, and it already sorted by score
    c = out;
}

Project buildProject(const std::vector<Candidate>& cands, const std::vector<Transcript>& transcripts,
                     const std::vector<MediaInfo>& media, const Settings& s, const BeatGrid& beats) {
    Project p; p.settings = s; p.musicBeats = beats;
    double total = 0; int videoClips = 0;
    std::vector<Candidate> chosen;
    for (auto& c : cands) {
        if (!c.selected) continue;
        if (!c.isImage && videoClips >= s.maxClips) continue;
        if (total + c.duration() > s.maxLength + 0.5) {
            if (c.isImage || total >= s.minLength) continue;
            // trim this clip to fit the ceiling if it still leaves a usable length
            Candidate t = c; t.end = transcripts[c.sourceIndex].snapToWordBoundary(c.start + (s.maxLength - total), false);
            if (t.duration() < std::max(2.0, s.minClip * 0.7)) continue;
            chosen.push_back(t); total += t.duration(); videoClips++;
            break;
        }
        chosen.push_back(c); total += c.duration(); if (!c.isImage) videoClips++;
    }
    // too short: extend the last video clip toward the next sentence end
    if (total < s.minLength) for (auto it = chosen.rbegin(); it != chosen.rend(); ++it) {
        if (it->isImage) continue;
        auto& tr = transcripts[it->sourceIndex]; double srcDur = media[it->sourceIndex].duration;
        double want = it->end + (s.minLength - total);
        double e = std::min({tr.snapToWordBoundary(want, false), srcDur, it->start + s.maxClip * 1.5});
        if (e > it->end) { total += e - it->end; it->end = e; }
        break;
    }
    std::vector<double> rel;
    if (!beats.empty()) {
        p.musicOffset = beats.beats.front();
        for (double b : beats.beats) rel.push_back(b - p.musicOffset);
    }
    double t = 0;
    for (size_t i = 0; i < chosen.size(); ++i) {
        auto& c = chosen[i];
        Clip k; k.sourcePath = media[c.sourceIndex].path; k.in = c.start; k.out = c.end;
        k.cropCenterX = c.cropCenterX; k.cropEndX = c.cropEndX; k.track = c.track; k.hook = c.hook;
        k.overlay = c.overlay; k.isImage = c.isImage;
        if (s.syncToBeats && !rel.empty()) {
            double want = t + k.duration();
            auto it = std::lower_bound(rel.begin(), rel.end(), want);
            double best = want, bd = 1e9;
            for (int d = -1; d <= 1; ++d) {
                auto j = it + d;
                if (j < rel.begin() || j >= rel.end()) continue;
                if (std::fabs(*j - want) < bd) { bd = std::fabs(*j - want); best = *j; }
            }
            double newDur = best - t, srcDur = c.isImage ? 1e9 : media[c.sourceIndex].duration;
            if (bd <= 0.6 && newDur >= (c.isImage ? 1.0 : s.minClip * 0.8) && k.in + newDur <= srcDur)
                k.out = k.in + newDur;
        }
        if (!c.isImage) k.words = transcripts[c.sourceIndex].wordsBetween(k.in, k.out);
        t += k.duration();
        p.clips.push_back(k);
    }
    return p;
}

} // namespace cm
