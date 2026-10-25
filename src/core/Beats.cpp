#include "core/Beats.h"
#include <Accelerate/Accelerate.h>
#include <cmath>
#include <algorithm>
#include <numeric>

namespace cm {

BeatGrid detectBeats(const std::vector<float>& x, int sr) {
    BeatGrid g;
    const int LOG2N = 11, N = 1 << LOG2N, H = N / 4;   // 2048 / 512
    if (x.size() < (size_t)N * 8 || sr <= 0) return g;
    const int frames = int((x.size() - N) / H);
    const double fps = double(sr) / H;

    FFTSetup setup = vDSP_create_fftsetup(LOG2N, kFFTRadix2);
    std::vector<float> win(N), buf(N), re(N / 2), im(N / 2), mag(N / 2), prev(N / 2, 0.f);
    vDSP_hann_window(win.data(), N, vDSP_HANN_NORM);
    DSPSplitComplex sc{re.data(), im.data()};
    std::vector<float> flux(frames, 0.f);

    for (int f = 0; f < frames; ++f) {
        vDSP_vmul(x.data() + (size_t)f * H, 1, win.data(), 1, buf.data(), 1, N);
        vDSP_ctoz((DSPComplex*)buf.data(), 2, &sc, 1, N / 2);
        vDSP_fft_zrip(setup, &sc, 1, LOG2N, FFT_FORWARD);
        vDSP_zvabs(&sc, 1, mag.data(), 1, N / 2);
        float acc = 0;
        for (int k = 1; k < N / 2; ++k) {
            float m = std::log1p(50.f * mag[k]);
            float d = m - prev[k];
            if (d > 0) acc += d;
            prev[k] = m;
        }
        flux[f] = acc;
    }
    vDSP_destroy_fftsetup(setup);

    // Remove slow envelope (local mean over ~0.6 s), half-wave rectify, normalize.
    int win2 = std::max(2, int(0.3 * fps));
    std::vector<float> env(frames, 0.f);
    for (int i = 0; i < frames; ++i) {
        int a = std::max(0, i - win2), b = std::min(frames - 1, i + win2);
        float s = 0; for (int j = a; j <= b; ++j) s += flux[j];
        env[i] = std::max(0.f, flux[i] - s / (b - a + 1));
    }
    float mx = *std::max_element(env.begin(), env.end());
    if (mx <= 0) return g;
    for (auto& v : env) v /= mx;

    // Onsets: local maxima above adaptive threshold.
    int pk = std::max(1, int(0.08 * fps));
    for (int i = pk; i < frames - pk; ++i) {
        bool isMax = true;
        for (int j = i - pk; j <= i + pk && isMax; ++j) if (env[j] > env[i]) isMax = false;
        if (isMax && env[i] > 0.12f) g.onsets.push_back(i / fps);
    }

    // Tempo via autocorrelation over 60..190 BPM with a mild prior around 120.
    int lagMin = int(fps * 60.0 / 190.0), lagMax = int(fps * 60.0 / 60.0);
    double bestScore = -1; int bestLag = 0;
    for (int lag = lagMin; lag <= lagMax && lag < frames / 2; ++lag) {
        double s = 0;
        for (int i = 0; i + lag < frames; ++i) s += env[i] * env[i + lag];
        s /= (frames - lag);
        double bpm = 60.0 * fps / lag;
        double prior = std::exp(-0.5 * std::pow(std::log2(bpm / 120.0) / 0.7, 2));
        s *= (0.6 + 0.4 * prior);
        if (s > bestScore) { bestScore = s; bestLag = lag; }
    }
    if (bestLag <= 0) return g;

    // Refine lag with parabolic interpolation on neighbours is overkill; use fractional
    // period search instead: scan small range around bestLag with 0.05 frame steps.
    double period = bestLag;
    {
        double bs = -1;
        for (double p = bestLag - 1.0; p <= bestLag + 1.0; p += 0.05) {
            double s = 0; int n = 0;
            for (double t = 0; t + p < frames; t += p) { s += env[int(t)] * env[int(t + p)]; ++n; }
            if (n && s / n > bs) { bs = s / n; period = p; }
        }
    }
    g.bpm = 60.0 * fps / period;

    // Phase: offset that maximises onset energy on the grid.
    double bestPhase = 0, bestE = -1;
    for (double ph = 0; ph < period; ph += 0.25) {
        double e = 0; int n = 0;
        for (double t = ph; t < frames; t += period) { e += env[int(t)]; ++n; }
        if (n && e / n > bestE) { bestE = e / n; bestPhase = ph; }
    }
    for (double t = bestPhase; t < frames; t += period) g.beats.push_back(t / fps);
    return g;
}

} // namespace cm
