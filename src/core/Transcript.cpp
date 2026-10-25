#include "core/Model.h"
#include <algorithm>
#include <cmath>
#include <cstdio>

namespace cm {

std::vector<Word> Transcript::wordsBetween(double a, double b) const {
    std::vector<Word> out;
    for (auto& s : sentences) {
        if (s.end < a || s.start > b) continue;
        for (auto& w : s.words) {
            double mid = (w.start + w.end) * 0.5;
            if (mid >= a && mid <= b) out.push_back(w);
        }
    }
    return out;
}

std::string Transcript::textBetween(double a, double b) const {
    std::string t;
    for (auto& w : wordsBetween(a, b)) { if (!t.empty()) t += ' '; t += w.text; }
    return t;
}

double Transcript::snapToWordBoundary(double t, bool preferStart) const {
    double best = t, bestD = 1e9;
    for (auto& s : sentences) {
        if (s.end < t - 2 || s.start > t + 2) continue;
        for (auto& w : s.words) {
            double cand = preferStart ? w.start : w.end;
            double d = std::fabs(cand - t);
            if (d < bestD) { bestD = d; best = cand; }
        }
    }
    // give a small breathing room: starts slightly earlier, ends slightly later
    return bestD < 1.5 ? (preferStart ? std::max(0.0, best - 0.12) : best + 0.18) : t;
}

double BeatGrid::nearest(double t) const {
    if (beats.empty()) return t;
    auto it = std::lower_bound(beats.begin(), beats.end(), t);
    double a = it == beats.end() ? beats.back() : *it;
    double b = it == beats.begin() ? beats.front() : *(it - 1);
    return std::fabs(a - t) < std::fabs(b - t) ? a : b;
}

double Project::duration() const {
    double d = 0;
    for (auto& c : clips) d += c.duration();
    return d;
}

std::string Script::publishText() const {
    std::string t = "TITLE\n" + title + "\n\nDESCRIPTION\n" + description + "\n\nHASHTAGS\n";
    for (auto& h : hashtags) t += (h.rfind('#', 0) == 0 ? h : "#" + h) + " ";
    return t + "\n";
}

std::string fmtTime(double s) {
    int m = int(s) / 60; double r = s - m * 60;
    char buf[32]; snprintf(buf, sizeof buf, "%d:%05.2f", m, r);
    return buf;
}

std::string lower(std::string s) {
    for (auto& c : s) c = (char)tolower((unsigned char)c);
    return s;
}

std::string trim(const std::string& s) {
    size_t a = s.find_first_not_of(" \t\r\n"), b = s.find_last_not_of(" \t\r\n");
    return a == std::string::npos ? "" : s.substr(a, b - a + 1);
}

} // namespace cm
