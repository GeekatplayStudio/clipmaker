#pragma once
#include "core/Model.h"

namespace cm {
// Onset-strength (spectral flux) + autocorrelation tempo estimate + phase fit.
BeatGrid detectBeats(const std::vector<float>& mono, int sampleRate);
}
