// FMQR — QR-Code nach ISO/IEC 18004: Byte-Modus, Level M, Version 1–10, beste Maske per Strafpunkten.
#include "FMQR.h"
#include <string.h>
#include <stdbool.h>

#define MAXV 10
static const int ECC_PER_BLOCK[MAXV + 1] = { 0, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26 };   // Level M
static const int NUM_BLOCKS[MAXV + 1]    = { 0,  1,  1,  1,  2,  2,  4,  4,  4,  5,  5 };

typedef struct {
    int size;
    uint8_t mod[FMQR_MAX_SIZE][FMQR_MAX_SIZE];   // [y][x], 1 = dunkel
    uint8_t fn[FMQR_MAX_SIZE][FMQR_MAX_SIZE];    // Funktionsmuster (nicht maskieren)
} QR;

static int rawModules(int v) {
    int r = (16 * v + 128) * v + 64;
    if (v >= 2) {
        int na = v / 7 + 2;
        r -= (25 * na - 10) * na - 55;
        if (v >= 7) r -= 36;
    }
    return r;
}
static int dataCodewords(int v) { return rawModules(v) / 8 - ECC_PER_BLOCK[v] * NUM_BLOCKS[v]; }

// ---- Reed-Solomon über GF(256), Polynom 0x11D ----
static uint8_t gmul(uint8_t x, uint8_t y) {
    int z = 0;
    for (int i = 7; i >= 0; i--) {
        z = (z << 1) ^ ((z >> 7) * 0x11D);
        z ^= ((y >> i) & 1) * x;
    }
    return (uint8_t)z;
}
static void rsDivisor(int deg, uint8_t *res) {
    memset(res, 0, (size_t)deg);
    res[deg - 1] = 1;
    uint8_t root = 1;
    for (int i = 0; i < deg; i++) {
        for (int j = 0; j < deg; j++) {
            res[j] = gmul(res[j], root);
            if (j + 1 < deg) res[j] ^= res[j + 1];
        }
        root = gmul(root, 0x02);
    }
}
static void rsRemainder(const uint8_t *data, int len, const uint8_t *div, int deg, uint8_t *res) {
    memset(res, 0, (size_t)deg);
    for (int i = 0; i < len; i++) {
        uint8_t f = data[i] ^ res[0];
        memmove(res, res + 1, (size_t)(deg - 1));
        res[deg - 1] = 0;
        for (int j = 0; j < deg; j++) res[j] ^= gmul(div[j], f);
    }
}

// ---- Funktionsmuster ----
static void setFn(QR *q, int x, int y, bool dark) { q->mod[y][x] = dark; q->fn[y][x] = 1; }

static void finder(QR *q, int cx, int cy) {
    for (int dy = -4; dy <= 4; dy++)
        for (int dx = -4; dx <= 4; dx++) {
            int x = cx + dx, y = cy + dy, adx = dx < 0 ? -dx : dx, ady = dy < 0 ? -dy : dy;
            int d = adx > ady ? adx : ady;
            if (x >= 0 && x < q->size && y >= 0 && y < q->size) setFn(q, x, y, d != 2 && d != 4);
        }
}
static void alignment(QR *q, int cx, int cy) {
    for (int dy = -2; dy <= 2; dy++)
        for (int dx = -2; dx <= 2; dx++) {
            int adx = dx < 0 ? -dx : dx, ady = dy < 0 ? -dy : dy;
            setFn(q, cx + dx, cy + dy, (adx > ady ? adx : ady) != 1);
        }
}
static void formatBits(QR *q, int mask) {
    int data = (0 << 3) | mask;                 // Level M = 00
    int rem = data;
    for (int i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >> 9) * 0x537);
    int bits = ((data << 10) | rem) ^ 0x5412;
    int n = q->size;
    for (int i = 0; i <= 5; i++) setFn(q, 8, i, (bits >> i) & 1);
    setFn(q, 8, 7, (bits >> 6) & 1);
    setFn(q, 8, 8, (bits >> 7) & 1);
    setFn(q, 7, 8, (bits >> 8) & 1);
    for (int i = 9; i < 15; i++) setFn(q, 14 - i, 8, (bits >> i) & 1);
    for (int i = 0; i < 8; i++) setFn(q, n - 1 - i, 8, (bits >> i) & 1);
    for (int i = 8; i < 15; i++) setFn(q, 8, n - 15 + i, (bits >> i) & 1);
    setFn(q, 8, n - 8, 1);                      // „Dark Module“
}
static void versionBits(QR *q, int v) {
    if (v < 7) return;
    int rem = v;
    for (int i = 0; i < 12; i++) rem = (rem << 1) ^ ((rem >> 11) * 0x1F25);
    long bits = ((long)v << 12) | rem;
    for (int i = 0; i < 18; i++) {
        bool b = (bits >> i) & 1;
        int a = q->size - 11 + i % 3, c = i / 3;
        setFn(q, a, c, b);
        setFn(q, c, a, b);
    }
}
static void functionPatterns(QR *q, int v) {
    int n = q->size;
    for (int i = 0; i < n; i++) { setFn(q, 6, i, i % 2 == 0); setFn(q, i, 6, i % 2 == 0); }
    finder(q, 3, 3); finder(q, n - 4, 3); finder(q, 3, n - 4);
    if (v >= 2) {
        int na = v / 7 + 2, pos[8];
        int step = (v * 4 + na * 2 + 1) / (na * 2 - 2) * 2;
        pos[0] = 6;
        for (int i = na - 1, p = n - 7; i >= 1; i--, p -= step) pos[i] = p;
        for (int i = 0; i < na; i++)
            for (int j = 0; j < na; j++)
                if (!((i == 0 && j == 0) || (i == 0 && j == na - 1) || (i == na - 1 && j == 0)))
                    alignment(q, pos[i], pos[j]);
    }
    formatBits(q, 0);                           // reserviert, echte Maske folgt
    versionBits(q, v);
}

static void placeCodewords(QR *q, const uint8_t *data, int len) {
    int n = q->size, i = 0;
    for (int right = n - 1; right >= 1; right -= 2) {
        if (right == 6) right = 5;
        for (int vert = 0; vert < n; vert++)
            for (int j = 0; j < 2; j++) {
                int x = right - j;
                bool up = ((right + 1) & 2) == 0;
                int y = up ? n - 1 - vert : vert;
                if (!q->fn[y][x] && i < len * 8) { q->mod[y][x] = (data[i >> 3] >> (7 - (i & 7))) & 1; i++; }
            }
    }
}

static void applyMask(QR *q, int m) {
    for (int y = 0; y < q->size; y++)
        for (int x = 0; x < q->size; x++) {
            if (q->fn[y][x]) continue;
            bool inv;
            switch (m) {
                case 0: inv = (x + y) % 2 == 0; break;
                case 1: inv = y % 2 == 0; break;
                case 2: inv = x % 3 == 0; break;
                case 3: inv = (x + y) % 3 == 0; break;
                case 4: inv = (x / 3 + y / 2) % 2 == 0; break;
                case 5: inv = x * y % 2 + x * y % 3 == 0; break;
                case 6: inv = (x * y % 2 + x * y % 3) % 2 == 0; break;
                default: inv = ((x + y) % 2 + x * y % 3) % 2 == 0; break;
            }
            q->mod[y][x] ^= inv;
        }
}

// Strafpunkte (Regeln 1, 2, 4 und vereinfachte 3) — jede Maske ist gültig, das wählt nur die gut lesbarste
static long penalty(const QR *q) {
    int n = q->size; long p = 0; int dark = 0;
    for (int y = 0; y < n; y++) {
        for (int pass = 0; pass < 2; pass++) {              // 0 = Zeile y, 1 = Spalte y
            int run = 1;
            for (int i = 1; i <= n; i++) {
                bool same = i < n && (pass ? q->mod[i][y] == q->mod[i - 1][y] : q->mod[y][i] == q->mod[y][i - 1]);
                if (same) run++;
                else { if (run >= 5) p += run - 2; run = 1; }
            }
            for (int i = 0; i + 6 < n; i++) {                // 1:1:3:1:1-Finder-Imitat
                uint8_t s[7];
                for (int k = 0; k < 7; k++) s[k] = pass ? q->mod[i + k][y] : q->mod[y][i + k];
                if (s[0] && !s[1] && s[2] && s[3] && s[4] && !s[5] && s[6]) p += 40;
            }
        }
        for (int x = 0; x < n; x++) {
            dark += q->mod[y][x];
            if (y + 1 < n && x + 1 < n) {
                uint8_t c = q->mod[y][x];
                if (c == q->mod[y][x + 1] && c == q->mod[y + 1][x] && c == q->mod[y + 1][x + 1]) p += 3;
            }
        }
    }
    int total = n * n;
    int k = ((dark * 20 - total * 10) < 0 ? -(dark * 20 - total * 10) : (dark * 20 - total * 10)) + total - 1;
    p += (k / total - 1) * 10;
    return p;
}

int fmqr_encode(const char *text, uint8_t *out) {
    int len = (int)strlen(text), v;
    for (v = 1; v <= MAXV; v++) {
        int ccBits = v <= 9 ? 8 : 16;
        if (4 + ccBits + 8 * len <= dataCodewords(v) * 8) break;
    }
    if (v > MAXV) return 0;

    // ---- Datenbits ----
    int cap = dataCodewords(v);
    uint8_t data[400]; memset(data, 0, sizeof data);
    int bit = 0;
    #define PUT(val, nb) do { for (int _i = (nb) - 1; _i >= 0; _i--, bit++) if (((val) >> _i) & 1) data[bit >> 3] |= (uint8_t)(0x80 >> (bit & 7)); } while (0)
    PUT(0x4, 4);
    PUT(len, v <= 9 ? 8 : 16);
    for (int i = 0; i < len; i++) PUT((uint8_t)text[i], 8);
    int term = cap * 8 - bit; if (term > 4) term = 4;
    bit += term;                                         // Terminator (Nullen)
    bit = (bit + 7) / 8 * 8;
    for (int pad = 0xEC; bit < cap * 8; pad ^= 0xEC ^ 0x11) PUT(pad, 8);
    #undef PUT

    // ---- Blöcke + Fehlerkorrektur, verschränkt ----
    int nb = NUM_BLOCKS[v], ecl = ECC_PER_BLOCK[v], raw = rawModules(v) / 8;
    int shortBlocks = nb - raw % nb, shortLen = raw / nb;
    uint8_t div[32], blocks[8][160], all[400];
    rsDivisor(ecl, div);
    for (int i = 0, k = 0; i < nb; i++) {
        int dl = shortLen - ecl + (i < shortBlocks ? 0 : 1);
        memset(blocks[i], 0, sizeof blocks[i]);
        memcpy(blocks[i], data + k, (size_t)dl);
        k += dl;
        uint8_t ec[32];
        rsRemainder(blocks[i], dl, div, ecl, ec);
        if (i < shortBlocks) blocks[i][dl] = 0;          // Platzhalter, wird übersprungen
        memcpy(blocks[i] + shortLen + 1 - ecl, ec, (size_t)ecl);
    }
    int n = 0;
    for (int i = 0; i <= shortLen; i++)
        for (int j = 0; j < nb; j++)
            if (i != shortLen - ecl || j >= shortBlocks) all[n++] = blocks[j][i];

    // ---- Matrix + beste Maske ----
    static QR q, best;
    long bestP = -1;
    for (int m = 0; m < 8; m++) {
        memset(&q, 0, sizeof q);
        q.size = v * 4 + 17;
        functionPatterns(&q, v);
        placeCodewords(&q, all, n);
        applyMask(&q, m);
        formatBits(&q, m);
        long p = penalty(&q);
        if (bestP < 0 || p < bestP) { bestP = p; best = q; }
    }
    for (int y = 0; y < best.size; y++)
        for (int x = 0; x < best.size; x++) out[y * best.size + x] = best.mod[y][x];
    return best.size;
}
