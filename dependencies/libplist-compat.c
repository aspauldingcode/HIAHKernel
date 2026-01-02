/*
 * libplist-compat.c
 * 
 * Compatibility shim to provide newer libplist API functions
 * that minimuxer/libimobiledevice need but AltSign's older libplist lacks.
 * 
 * These functions bridge the gap between libplist 2.2+ API and older versions.
 */

#include <plist/plist.h>
#include <string.h>
#include <stdlib.h>

/*
 * plist_bool_val_is_true - Check if a boolean plist node is true
 * Available in libplist 2.3+, not in older versions
 */
int plist_bool_val_is_true(plist_t node)
{
    if (!node) return 0;
    if (plist_get_node_type(node) != PLIST_BOOLEAN) return 0;
    
    uint8_t val = 0;
    plist_get_bool_val(node, &val);
    return val != 0;
}

/*
 * plist_get_data_ptr - Get pointer to data without copying
 * Available in libplist 2.3+, provides direct access to internal buffer
 * This implementation returns a copy (caller must free) for compatibility
 */
const char* plist_get_data_ptr(plist_t node, uint64_t *length)
{
    if (!node || !length) return NULL;
    if (plist_get_node_type(node) != PLIST_DATA) return NULL;
    
    char *data = NULL;
    plist_get_data_val(node, &data, length);
    return data;
}

/*
 * plist_get_string_ptr - Get pointer to string without copying
 * Available in libplist 2.3+
 * This implementation returns a copy (caller must free) for compatibility
 */
const char* plist_get_string_ptr(plist_t node, uint64_t *length)
{
    if (!node) return NULL;
    if (plist_get_node_type(node) != PLIST_STRING) return NULL;
    
    char *str = NULL;
    plist_get_string_val(node, &str);
    if (str && length) {
        *length = strlen(str);
    }
    return str;
}

/*
 * plist_string_val_compare - Compare string node value to a C string
 * Available in libplist 2.3+
 * Returns 0 if equal, non-zero otherwise
 */
int plist_string_val_compare(plist_t node, const char *cmpval)
{
    if (!node || !cmpval) return -1;
    if (plist_get_node_type(node) != PLIST_STRING) return -1;
    
    char *str = NULL;
    plist_get_string_val(node, &str);
    if (!str) return -1;
    
    int result = strcmp(str, cmpval);
    free(str);
    return result;
}

