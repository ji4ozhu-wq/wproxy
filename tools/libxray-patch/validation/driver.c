// Validation driver for the rebuilt (patched) libXray macOS static library.
// Reads simple line commands from stdin and prints the libXray response JSON.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

extern char* CGoInvoke(char* requestJSON);
extern void CGoFree(char* value);

static char* read_file(const char* path) {
    FILE* f = fopen(path, "rb");
    if (!f) return NULL;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return NULL; }
    long size = ftell(f);
    if (size < 0) { fclose(f); return NULL; }
    rewind(f);
    char* data = (char*)malloc((size_t)size + 1);
    if (!data) { fclose(f); return NULL; }
    size_t read = fread(data, 1, (size_t)size, f);
    fclose(f);
    data[read] = '\0';
    return data;
}

static char* json_escape(const char* text) {
    size_t len = strlen(text);
    char* out = (char*)malloc(len * 6 + 1);
    if (!out) return NULL;
    size_t i = 0;
    for (size_t p = 0; p < len; p++) {
        unsigned char c = (unsigned char)text[p];
        switch (c) {
            case '"': out[i++] = '\\'; out[i++] = '"'; break;
            case '\\': out[i++] = '\\'; out[i++] = '\\'; break;
            case '\n': out[i++] = '\\'; out[i++] = 'n'; break;
            case '\r': out[i++] = '\\'; out[i++] = 'r'; break;
            case '\t': out[i++] = '\\'; out[i++] = 't'; break;
            default:
                if (c < 0x20) {
                    i += (size_t)snprintf(out + i, 7, "\\u%04x", c);
                } else {
                    out[i++] = (char)c;
                }
        }
    }
    out[i] = '\0';
    return out;
}

static void emit(char* response) {
    if (!response) {
        printf("RESP {\"success\":false,\"data\":null,\"error\":\"null response from libXray\"}\n");
        return;
    }
    printf("RESP %s\n", response);
    fflush(stdout);
    CGoFree(response);
}

static void invoke_with_config(const char* method, const char* path) {
    char* config = read_file(path);
    if (!config) {
        printf("RESP {\"success\":false,\"data\":null,\"error\":\"cannot read config file\"}\n");
        return;
    }
    char* escaped = json_escape(config);
    free(config);
    if (!escaped) {
        printf("RESP {\"success\":false,\"data\":null,\"error\":\"cannot escape config\"}\n");
        return;
    }
    size_t fmt_len = strlen(escaped) + 256;
    char* request = (char*)malloc(fmt_len);
    snprintf(request, fmt_len,
             "{\"apiVersion\":3,\"method\":\"%s\",\"payload\":{\"xrayJson\":\"%s\"}}",
             method, escaped);
    free(escaped);
    emit(CGoInvoke(request));
    free(request);
}

int main(void) {
    char line[4096];
    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\r\n")] = '\0';
        if (line[0] == '\0') continue;
        if (strcmp(line, "quit") == 0) break;
        if (strcmp(line, "version") == 0) {
            emit(CGoInvoke("{\"apiVersion\":3,\"method\":\"xrayVersion\"}"));
        } else if (strcmp(line, "state") == 0) {
            emit(CGoInvoke("{\"apiVersion\":3,\"method\":\"getXrayState\"}"));
        } else if (strcmp(line, "stop") == 0) {
            emit(CGoInvoke("{\"apiVersion\":3,\"method\":\"stopXray\"}"));
        } else if (strcmp(line, "stats") == 0) {
            emit(CGoInvoke("{\"apiVersion\":3,\"method\":\"getTrafficStats\"}"));
        } else if (strncmp(line, "stats ", 6) == 0) {
            char request[512];
            snprintf(request, sizeof(request),
                     "{\"apiVersion\":3,\"method\":\"getTrafficStats\",\"payload\":{\"inboundTag\":\"%s\"}}",
                     line + 6);
            emit(CGoInvoke(request));
        } else if (strncmp(line, "test ", 5) == 0) {
            invoke_with_config("testXray", line + 5);
        } else if (strncmp(line, "run ", 4) == 0) {
            invoke_with_config("runXray", line + 4);
        } else {
            printf("RESP {\"success\":false,\"data\":null,\"error\":\"unknown command\"}\n");
        }
        fflush(stdout);
    }
    return 0;
}
