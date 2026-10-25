#pragma once
#include "core/Model.h"

namespace cm {

// Offline fallback: keyword relevance + "hook" signals over sliding windows.
// Transcripts are indexed like media; image sources have an empty transcript.
std::vector<Candidate> heuristicCandidates(const std::vector<Transcript>& transcripts,
                                           const std::vector<MediaInfo>& media,
                                           const std::string& idea, const Settings& s);
// Offline script + publishing copy built from the chosen candidates.
Script heuristicScript(const std::vector<Candidate>& c, const std::vector<MediaInfo>& media,
                       const std::string& idea, const Settings& s);
// Narrative text of the current candidate list (used when the AI gives none, and for display).
std::string describeScript(const std::vector<Candidate>& c, const std::vector<MediaInfo>& media);

// Prompt text handed to the LLM (Anthropic / Ollama / OpenAI-compatible).
std::string buildSystemPrompt();
std::string buildUserPrompt(const std::vector<Transcript>& transcripts, const std::vector<MediaInfo>& media,
                            const std::vector<std::string>& imageVisuals, const std::string& idea, const Settings& s);

// Snap to word boundaries, clamp durations, drop overlaps, sort by score.
void refineCandidates(std::vector<Candidate>& c, const std::vector<Transcript>& transcripts,
                      const std::vector<MediaInfo>& media, const Settings& s);

// Pick selected candidates up to target length, snap cut points to music beats.
Project buildProject(const std::vector<Candidate>& c, const std::vector<Transcript>& transcripts,
                     const std::vector<MediaInfo>& media, const Settings& s, const BeatGrid& beats);

} // namespace cm
