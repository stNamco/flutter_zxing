#pragma once

#include <cstdint>
#include <algorithm>
#include <cstring>

/// CLAHE (Contrast Limited Adaptive Histogram Equalization)
/// Improves local contrast for QR code detection under uneven lighting.
/// Operates in-place on a grayscale (luminance) image buffer.
///
/// @param data     Grayscale image buffer (modified in-place)
/// @param width    Image width in pixels
/// @param height   Image height in pixels
/// @param tilesX   Number of horizontal tiles (default: 8)
/// @param tilesY   Number of vertical tiles (default: 8)
/// @param clipLimit Contrast limit per tile histogram bin (default: 2.0)
inline void applyCLAHE(
    uint8_t* data,
    int width,
    int height,
    int tilesX = 8,
    int tilesY = 8,
    double clipLimit = 2.0)
{
    if (data == nullptr || width <= 0 || height <= 0) return;
    if (tilesX <= 0 || tilesY <= 0) return;

    const int NUM_BINS = 256;
    const int tileW = width / tilesX;
    const int tileH = height / tilesY;

    if (tileW <= 0 || tileH <= 0) return;

    const int numPixelsPerTile = tileW * tileH;

    // Clip limit in absolute counts
    const int clipCount = std::max(1, static_cast<int>(clipLimit * numPixelsPerTile / NUM_BINS));

    // Allocate CDF LUTs for all tiles: tilesY * tilesX * 256
    const int totalTiles = tilesX * tilesY;
    std::vector<uint8_t> cdfs(totalTiles * NUM_BINS);

    // Step 1: Build clipped histogram and CDF for each tile
    for (int ty = 0; ty < tilesY; ++ty) {
        for (int tx = 0; tx < tilesX; ++tx) {
            int hist[NUM_BINS] = {};
            const int startX = tx * tileW;
            const int startY = ty * tileH;

            // Build histogram
            for (int y = startY; y < startY + tileH; ++y) {
                for (int x = startX; x < startX + tileW; ++x) {
                    hist[data[y * width + x]]++;
                }
            }

            // Clip histogram and redistribute
            int excess = 0;
            for (int i = 0; i < NUM_BINS; ++i) {
                if (hist[i] > clipCount) {
                    excess += hist[i] - clipCount;
                    hist[i] = clipCount;
                }
            }
            const int increment = excess / NUM_BINS;
            const int remainder = excess % NUM_BINS;
            for (int i = 0; i < NUM_BINS; ++i) {
                hist[i] += increment;
            }
            // Distribute remainder evenly
            for (int i = 0; i < remainder; ++i) {
                hist[i * NUM_BINS / remainder]++;
            }

            // Build CDF (cumulative distribution) and normalize to [0, 255]
            uint8_t* cdf = &cdfs[(ty * tilesX + tx) * NUM_BINS];
            int cumSum = 0;
            for (int i = 0; i < NUM_BINS; ++i) {
                cumSum += hist[i];
                cdf[i] = static_cast<uint8_t>(
                    std::min(255, cumSum * 255 / numPixelsPerTile));
            }
        }
    }

    // Step 2: Interpolate CDFs for each pixel
    // Use a temporary buffer to avoid read-after-write issues
    std::vector<uint8_t> output(width * height);

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const uint8_t pixel = data[y * width + x];

            // Find the tile center coordinates for interpolation
            // Map pixel position to tile-center coordinate space
            const double fx = (static_cast<double>(x) / tileW) - 0.5;
            const double fy = (static_cast<double>(y) / tileH) - 0.5;

            int tx0 = static_cast<int>(fx);
            int ty0 = static_cast<int>(fy);

            // Clamp tile indices
            tx0 = std::max(0, std::min(tx0, tilesX - 2));
            ty0 = std::max(0, std::min(ty0, tilesY - 2));
            const int tx1 = tx0 + 1;
            const int ty1 = ty0 + 1;

            // Interpolation weights
            const double ax = fx - tx0;
            const double ay = fy - ty0;
            const double cax = std::max(0.0, std::min(1.0, ax));
            const double cay = std::max(0.0, std::min(1.0, ay));

            // Bilinear interpolation of 4 neighboring tile CDFs
            const uint8_t v00 = cdfs[(ty0 * tilesX + tx0) * NUM_BINS + pixel];
            const uint8_t v01 = cdfs[(ty0 * tilesX + tx1) * NUM_BINS + pixel];
            const uint8_t v10 = cdfs[(ty1 * tilesX + tx0) * NUM_BINS + pixel];
            const uint8_t v11 = cdfs[(ty1 * tilesX + tx1) * NUM_BINS + pixel];

            const double top = v00 * (1.0 - cax) + v01 * cax;
            const double bottom = v10 * (1.0 - cax) + v11 * cax;
            const double value = top * (1.0 - cay) + bottom * cay;

            output[y * width + x] = static_cast<uint8_t>(
                std::max(0.0, std::min(255.0, value)));
        }
    }

    // Copy result back
    std::memcpy(data, output.data(), width * height);
}
