#include "tracing.h"

// Define the GUID to use in TraceLoggingProviderRegister
// {85A99459-1F1D-49BD-B3DC-E5EF2AD0C2C8}

TRACELOGGING_DEFINE_PROVIDER(g_hTraceLoggingProvider, "Microsoft.V8JSI", (0x85a99459, 0x1f1d, 0x49bd, 0xb3, 0xdc, 0xe5, 0xef, 0x2a, 0xd0, 0xc2, 0xc8));
