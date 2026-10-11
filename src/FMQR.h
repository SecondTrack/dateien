// FMQR — minimaler QR-Code-Encoder (Byte-Modus, Fehlerkorrektur M, Version 1–10).
// iOS 6 hat keinen CIQRCodeGenerator (erst iOS 7), daher eigen.
#ifndef FMQR_H
#define FMQR_H
#include <stdint.h>

#define FMQR_MAX_SIZE 57            // Version 10 = 57 x 57 Module

// Kodiert text; schreibt size*size Module (1 = dunkel) zeilenweise nach out.
// Gibt die Seitenlänge zurück, 0 wenn der Text zu lang ist (> 213 Byte).
int fmqr_encode(const char *text, uint8_t *out);

#endif
