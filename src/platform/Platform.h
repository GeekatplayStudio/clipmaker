// ClipMaker — Geekatplay Studio · Vladimir Chopine
#pragma once
#include "core/Model.h"

// macOS implementations (AVFoundation / Speech / Vision / NSURLSession).
namespace cm {

MediaInfo probeMedia(const std::string& path);
std::vector<float> decodeMonoPCM(const std::string& path, int sampleRate, std::string* err);

// On-device speech recognition with word timings. Chunks long files automatically.
Transcript transcribeFile(const std::string& path, const std::string& locale,
                          const Progress& progress, std::string* err);

// Normalized x (0..1) of the main subject at time t, or -1 when nothing was found.
double detectSubjectCenterX(const std::string& path, double t);
// Samples the subject position across the candidate and fills cropCenterX / cropEndX.
void trackSubject(Candidate& c, const std::string& path);

// LLM edit proposal. Returns empty + err on failure (caller falls back to heuristic).
std::vector<Candidate> aiSelectSegments(const Settings& s, const std::vector<Transcript>& transcripts,
                                        const std::vector<MediaInfo>& media, const std::vector<std::string>& imageVisuals,
                                        const std::string& idea, Script& script, std::string* err);

// Vision classification labels for a frame (or a still image when t < 0), e.g. "person, desk, laptop".
std::string describeFrame(const std::string& path, double t);

// Still image → cached short video (max 1920 px) so it can live in the AVFoundation composition.
std::string imageToVideo(const std::string& imagePath, double seconds, std::string* err);

// Writes publishing copy next to the rendered file.
void saveSidecar(const std::string& videoPath, const Script& script, const std::string& narrative);

bool renderProject(const Project& p, const std::string& outPath, const Progress& progress, std::string* err);

// Transcript cache (~/Library/Caches/ClipMaker).
bool loadTranscriptCache(const std::string& mediaPath, Transcript& out);
void saveTranscriptCache(const std::string& mediaPath, const Transcript& t);
std::string outputDirectory();

// Test helper: synthesize a talking-head style sample video with TTS narration.
int dumpFrames(const std::string& videoPath, const std::string& outDir, std::string* err);
bool makeSampleVideo(const std::string& outPath, const std::string& script, std::string* err);

} // namespace cm
