/* AvroBangla Engine - Combined C FFI Header */
#ifndef AVROBANGLA_ENGINE_H
#define AVROBANGLA_ENGINE_H

/* Include all riti FFI functions */
#include "riti.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Convert a Unicode character (from NSEvent.characters) to a riti keycode.
 * Returns 0 if the character is not mapped.
 */
uint16_t avro_keycode_for_char(uint32_t ch);

#ifdef __cplusplus
}
#endif

#endif /* AVROBANGLA_ENGINE_H */
