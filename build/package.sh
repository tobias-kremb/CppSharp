#!/usr/bin/env bash
# package.sh — gepatchtes CppSharp als NuGet paketieren (aehnlich offiziellem Paket)
set -euo pipefail

# ======= ANPASSEN =======
CPPSHARP_DIR="/d/Projekte/CppSharp"
FEED_DIR="/d/Projekte/modules/NuGetLocal"
CONFIGURATION="Release"
PLATFORM="x64"
TFM="net10.0"
VER="1.0.7"
# ========================

MSBUILD=$(ls "/c/Program Files/Microsoft Visual Studio/2022/"*/MSBuild/Current/Bin/MSBuild.exe 2>/dev/null | head -1 || true)
if [ -z "$MSBUILD" ]; then
    echo "FEHLER: MSBuild.exe nicht gefunden (VS 2022 mit C++-Workload?)."
    exit 1
fi
echo "MSBuild: $MSBUILD"

COMMIT=$(git -C "$CPPSHARP_DIR" rev-parse --short HEAD)
VERSION="$VER-$COMMIT"
echo "Paket-Version: $VERSION (CppSharp @ $COMMIT)"

cd "$CPPSHARP_DIR/build"

echo "=== 1/5 Solution generieren ==="
sh build.sh generate -configuration $CONFIGURATION -platform $PLATFORM

echo "=== 2/5 Bauen (MIT ref-Assemblies) ==="
"$MSBUILD" "$CPPSHARP_DIR/CppSharp.sln" \
    -p:Configuration=$CONFIGURATION -p:Platform=$PLATFORM \
    -p:ProduceReferenceAssembly=true \
    -restore -v:minimal -nologo

echo "=== 3/5 prepack ==="
rm -rf "$CPPSHARP_DIR/artifacts/package"          # Staging sauber (keine Stale-Copies)
"$MSBUILD" "$CPPSHARP_DIR/CppSharp.sln" -t:prepack \
    -p:Configuration=$CONFIGURATION -p:Platform=$PLATFORM -p:ProduceReferenceAssembly=true -v:minimal -nologo

echo "--- CLI + native Parser-Familie ins Paket-Staging legen ---"
# Der Build-Output-Ordner der CLI-DLL enthaelt die GESAMTE native Familie:
# CppSharp.Parser.CLI.dll, CppSharp.CppParser.dll, Std-symbols.dll, ijwhost.dll, LLVM-DLLs
CLIDLL=$(find "$CPPSHARP_DIR" -name "CppSharp.Parser.CLI.dll" \
    -not -path "*/obj/*" -not -path "*/artifacts/*" 2>/dev/null | head -1)
if [ -z "$CLIDLL" ]; then
    echo "FEHLER: CppSharp.Parser.CLI.dll im Build-Output nicht gefunden."
    exit 1
fi
NATIVE_SRC=$(dirname "$CLIDLL")
echo "Quelle: $NATIVE_SRC"

REFDIR="$CPPSHARP_DIR/artifacts/package/ref/$TFM"
LIBDIR="$CPPSHARP_DIR/artifacts/package/runtimes/win-x64/lib/$TFM"
NATDIR="$CPPSHARP_DIR/artifacts/package/runtimes/win-x64/native"
mkdir -p "$REFDIR" "$LIBDIR" "$NATDIR"

# 1) CLI-DLL als Compile-Referenz (ref/)
cp -v "$CLIDLL" "$REFDIR/"

# 2) GESAMTE native Familie in den lib/-Zweig: NuGet kopiert sie mit RID
#    zusammen mit den managed DLLs ins Output-WURZELVERZEICHNIS -> Loader findet alles
cp -v "$NATIVE_SRC"/*.dll "$LIBDIR/"

# 3) native-Sektion wie im offiziellen Paket (CppSharp.CppParser.dll + Std-symbols.dll
#    sind dort schon per PackNativeLibs gelandet; wir ergaenzen ijwhost & Co.)
cp -v "$NATIVE_SRC"/*.dll "$NATDIR/"

echo "=== 4/5 packen (Version per Property, wie die CI) ==="
"$MSBUILD" -t:restore "$CPPSHARP_DIR/src/Package/CppSharp.Package.csproj" \
    -p:Configuration=$CONFIGURATION -p:Platform=$PLATFORM -v:minimal -nologo
"$MSBUILD" -t:pack "$CPPSHARP_DIR/src/Package/CppSharp.Package.csproj" \
    -p:Configuration=$CONFIGURATION -p:Platform=$PLATFORM -p:Version="$VERSION" \
    -p:PackageOutputPath="$CPPSHARP_DIR/artifacts" -v:minimal -nologo

"$MSBUILD" -t:restore "$CPPSHARP_DIR/src/Runtime/CppSharp.Runtime.csproj" \
    -p:Configuration=$CONFIGURATION -p:Platform=$PLATFORM -v:minimal -nologo
"$MSBUILD" -t:pack "$CPPSHARP_DIR/src/Runtime/CppSharp.Runtime.csproj" \
    -p:Configuration=$CONFIGURATION -p:Platform=$PLATFORM -p:Version="$VERSION" \
    -p:PackageOutputPath="$CPPSHARP_DIR/artifacts" -v:minimal -nologo

echo "=== 5/5 Feed + Verifikation ==="
mkdir -p "$FEED_DIR"
cp -v "$CPPSHARP_DIR/artifacts/CppSharp.$VERSION.nupkg" "$FEED_DIR/"
cp -v "$CPPSHARP_DIR/artifacts/CppSharp.Runtime.$VERSION.nupkg" "$FEED_DIR/"

CPPS_NUPKG="$FEED_DIR/CppSharp.$VERSION.nupkg"
RUNTIME_NUPKG="$FEED_DIR/CppSharp.Runtime.$VERSION.nupkg"
if [ ! -f "$CPPS_NUPKG" ]; then
    echo "FEHLER: $CPPS_NUPKG nicht erzeugt."
    exit 1
fi

echo ""
echo "=== Strukturpruefung ==="
FAIL=0

# 1) Compile-Referenzen: alle managed DLLs muessen unter ref/ liegen
for dll in CppSharp.dll CppSharp.AST.dll CppSharp.Generator.dll \
           CppSharp.Parser.CLI.dll CppSharp.Runtime.dll; do
    if unzip -l "$CPPS_NUPKG" | grep -q "ref/$TFM/$dll"; then
        echo "OK: ref/$TFM/$dll"
    else
        echo "FEHLER: ref/$TFM/$dll fehlt"; FAIL=1
    fi
done

# 2) Laufzeit-Assets: alle managed DLLs muessen im lib/-Zweig liegen
for dll in CppSharp.dll CppSharp.AST.dll CppSharp.Generator.dll \
           CppSharp.Parser.CLI.dll CppSharp.Runtime.dll; do
    if unzip -l "$CPPS_NUPKG" | grep -q "runtimes/win-x64/lib/$TFM/$dll"; then
        echo "OK: runtimes/win-x64/lib/$TFM/$dll"
    else
        echo "FEHLER: runtimes/win-x64/lib/$TFM/$dll fehlt"; FAIL=1
    fi
done

# 3) native Familie im lib/-Zweig (ENTSCHEIDEND fuer den Loader!)
for dll in CppSharp.CppParser.dll Std-symbols.dll; do
    if unzip -l "$CPPS_NUPKG" | grep -q "runtimes/win-x64/lib/$TFM/$dll"; then
        echo "OK: $dll im lib/-Zweig"
    else
        echo "FEHLER: $dll fehlt im lib/-Zweig"; FAIL=1
    fi
done

# 4) native-Zweig (runtimes/win-x64/native/) — Bestueckung plausibel?
if unzip -l "$CPPS_NUPKG" | grep -q "runtimes/win-x64/native/CppSharp.CppParser.dll"; then
    echo "OK: native-Zweig bestueckt"
else
    echo "HINWEIS: native-Zweig leer (nur kritisch, falls benoetigt)"
fi

# 5) Runtime-Paket separat pruefen (flaches lib/-Layout, TFM ist netstandard2.1!)
if [ ! -f "$RUNTIME_NUPKG" ]; then
    echo "FEHLER: $RUNTIME_NUPKG nicht erzeugt."; FAIL=1
elif ! unzip -l "$RUNTIME_NUPKG" | grep -qE "lib/[^/]+/CppSharp\.Runtime\.dll"; then
    echo "FEHLER: CppSharp.Runtime.dll fehlt im Runtime-Paket"; FAIL=1
else
    echo "OK: Runtime-Paket"
fi

if [ "$FAIL" -ne 0 ]; then
    echo ""
    echo "Paket unvollstaendig - NICHT verwenden."
    exit 1
fi

echo ""
echo "Fertig. Im Feed: $FEED_DIR"
ls -la "$FEED_DIR"/*.nupkg
echo ""
echo "Generator-Projekt:"
echo "  <PackageReference Include=\"CppSharp\" Version=\"$VERSION\" />"
echo "  <RuntimeIdentifier>win-x64</RuntimeIdentifier>  (Pflicht!)"