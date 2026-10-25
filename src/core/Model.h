// ClipMaker — Geekatplay Studio · Vladimir Chopine
#pragma once
#include <string>
#include <vector>
#include <functional>
#include <map>

namespace cm {

struct Word { double start = 0, end = 0; std::string text; };

struct Sentence {
    double start = 0, end = 0;
    std::string text;
    std::vector<Word> words;
};

struct Transcript {
    std::vector<Sentence> sentences;
    double duration = 0;
    bool empty() const { return sentences.empty(); }
    std::vector<Word> wordsBetween(double a, double b) const;
    std::string textBetween(double a, double b) const;
    // Move t to the nearest word boundary so cuts never land mid-word.
    double snapToWordBoundary(double t, bool preferStart) const;
};

struct MediaInfo {
    std::string path;
    double duration = 0;
    int width = 0, height = 0;
    double fps = 30;
    bool hasAudio = false, hasVideo = false, isImage = false;
    bool ok = false;
    std::string error;
};

struct BeatGrid {
    double bpm = 0;
    std::vector<double> beats;   // regular grid (seconds)
    std::vector<double> onsets;  // detected transients (seconds)
    bool empty() const { return beats.empty(); }
    double nearest(double t) const;
};

struct Candidate {
    int sourceIndex = 0;
    double start = 0, end = 0;
    double score = 0;            // 0..100
    std::string hook, reason, text;
    std::string overlay;         // on-screen text for this clip (images, or suggested by the planner)
    std::string visual;          // what the frames show (Vision classification labels)
    bool isImage = false;
    double cropCenterX = 0.5;    // normalized subject x at clip start (9:16 reframe)
    double cropEndX = 0.5;       // ... at clip end (pan between them)
    std::vector<std::pair<double,double>> track; // (fraction of clip, subject x) keyframes
    bool selected = true;
    double duration() const { return end - start; }
};

enum class CaptionStyle { BoldPop = 0, Karaoke, Minimal, Outline, None };
enum class ScreenPos { Top = 0, Upper, Center, Lower, Bottom };
inline double screenPosY(ScreenPos p) {   // fraction from bottom for the caption block
    switch (p) { case ScreenPos::Top: return 0.82; case ScreenPos::Upper: return 0.66; case ScreenPos::Center: return 0.47;
                 case ScreenPos::Lower: return 0.30; default: return 0.14; }
}

// The proposed edit + publishing copy, shown to the user for approval.
struct Script {
    std::string narrative;       // human-readable editing script
    std::string title, description;
    std::vector<std::string> hashtags;
    std::string publishText() const;
};

struct Settings {
    enum Provider { Heuristic = 0, Anthropic, Ollama, OpenAICompat };
    Provider provider = Heuristic;
    std::string apiKey, model, baseURL;
    std::string locale = "en-US";

    double minLength = 20, maxLength = 40;
    int maxClips = 4;
    double minClip = 3, maxClip = 15;
    double slideDuration = 4;    // seconds per still image

    std::string musicPath;
    double musicGain = 0.2;
    bool keepVoice = true;
    bool syncToBeats = true;

    CaptionStyle captionStyle = CaptionStyle::BoldPop;
    double fontSize = 64;
    ScreenPos captionPos = ScreenPos::Lower;
    ScreenPos hookPos = ScreenPos::Top;
    std::string fontName = "Helvetica-Bold";
    bool showHook = true;

    bool smartReframe = true;
    bool kenBurns = true;
    int width = 1080, height = 1920;
    double fps = 30;
};

struct Clip {
    std::string sourcePath;
    double in = 0, out = 0;      // source seconds
    double cropCenterX = 0.5, cropEndX = 0.5;
    std::vector<std::pair<double,double>> track;
    std::string hook, overlay;
    bool isImage = false;
    std::vector<Word> words;     // source-time words inside [in,out]
    double duration() const { return out - in; }
};

struct Project {
    std::vector<Clip> clips;
    Settings settings;
    BeatGrid musicBeats;
    double musicOffset = 0;      // where in the music file composition t=0 lands
    double duration() const;
};

using Progress = std::function<void(double fraction, const std::string& message)>;

std::string fmtTime(double s);
std::string lower(std::string s);
std::string trim(const std::string& s);

} // namespace cm
