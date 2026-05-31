# Building pgvector for Windows PostgreSQL

## Problem
The EDB PostgreSQL installer for Windows does NOT include pgvector. GitHub releases don't provide pre-built Windows binaries. Cross-compiling from WSL via MinGW fails because Linux PG headers reference `sys/socket.h`.

## Solution: Build with MSVC on Windows

### Prerequisites
- Visual Studio 2022 Community with MSVC (cl.exe)
- PostgreSQL 18 Windows installation
- pgvector source from GitHub releases

### Build Steps

1. Copy source to Windows: `cp -r /tmp/pgvector-0.8.1 /mnt/c/Users/$USER/Desktop/`
2. Compile each .c file with cl.exe using PG include paths
3. Link into vector.dll against postgres.lib
4. Install into PG directories (requires admin PowerShell)
5. Run CREATE EXTENSION vector;

### Key Pitfalls
- MinGW cross-compile from WSL fails (Linux PG headers reference sys/socket.h)
- Makefile.win mangles paths with spaces — compile individually
- Admin required to copy into C:\Program Files\PostgreSQL\18\lib\

### Verified
VS 2022 Community (MSVC 14.50), PG 18.4 EDB. 19 source files → 279KB vector.dll.
