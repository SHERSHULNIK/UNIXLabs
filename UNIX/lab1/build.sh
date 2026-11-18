#!/bin/sh

TMP=
CHILD=
PARTIAL=

EX_USAGE=1
EX_NOSRC=2
EX_NOOUT=3
EX_BADTYPE=4
EX_MKTEMP=5
EX_NOTOOL=6
EX_COMPILE=7
EX_NORESULT=8
EX_BADNAME=9

usage() {
    echo "Использование: $0 [-h] <исходный_файл>" >&2
    echo "Поддерживаются: .c  .cpp/.cc/.cxx/.C  .tex" >&2
}

die() {
    code=$1
    shift
    echo "$0: ошибка: $*" >&2
    exit "$code"
}

cleanup() {
    trap - EXIT HUP INT QUIT TERM
    if [ -n "$CHILD" ]; then
        kill "$CHILD" 2>/dev/null
        wait "$CHILD" 2>/dev/null
    fi
    if [ -n "$PARTIAL" ]; then
        rm -f -- "$PARTIAL"
    fi
    if [ -n "$TMP" ] && [ -d "$TMP" ]; then
        rm -rf -- "$TMP"
    fi
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 131' QUIT
trap 'exit 143' TERM

run() {
    "$@" &
    CHILD=$!
    wait "$CHILD"
    rc=$?
    CHILD=
    return "$rc"
}

# Первая найденная в PATH программа из списка.
find_tool() {
    for t in "$@"; do
        if command -v "$t" >/dev/null 2>&1; then
            echo "$t"
            return 0
        fi
    done
    return 1
}

case $1 in
    -h|--help) usage; exit 0 ;;
esac
[ $# -eq 1 ] || { usage; exit "$EX_USAGE"; }

src=$1
[ -f "$src" ] && [ -r "$src" ] || die "$EX_NOSRC" "файл '$src' не найден или не читается"

srcdir=$(cd "$(dirname -- "$src")" && pwd) || die "$EX_NOSRC" "не удалось определить каталог '$src'"
srcname=$(basename -- "$src")
srcabs=$srcdir/$srcname

line=$(grep -E '(//|/\*|^[[:space:]]*\*|%|#)[[:space:]]*Output:' -- "$src" | head -n 1)
[ -n "$line" ] || die "$EX_NOOUT" "в '$src' нет комментария 'Output: <имя>'"

out=$(printf '%s\n' "$line" |
      sed -e 's/^.*Output:[[:space:]]*//' \
          -e 's/[[:space:]].*$//' \
          -e 's/\*\/$//')
[ -n "$out" ] || die "$EX_NOOUT" "после 'Output:' не указано имя файла"

case $out in
    */*|-*|.|..) die "$EX_BADNAME" "недопустимое имя выходного файла: '$out'" ;;
esac
[ "$out" != "$srcname" ] || die "$EX_BADNAME" "выходной файл совпадает с исходным"

case $srcname in
    *.c)                        kind=c ;;
    *.cpp|*.cc|*.cxx|*.C)       kind=cxx ;;
    *.tex)                      kind=tex ;;
    *) die "$EX_BADTYPE" "неподдерживаемый тип файла: '$srcname'" ;;
esac

TMP=$(mktemp -d "${TMPDIR:-/tmp}/build.XXXXXX") || { TMP=; die "$EX_MKTEMP" "mktemp не смог создать каталог"; }
[ -d "$TMP" ] || { TMP=; die "$EX_MKTEMP" "mktemp не создал каталог"; }

case $kind in
    c)
        cc=$(find_tool "${CC:-}" cc gcc clang) || die "$EX_NOTOOL" "не найден компилятор C"
        run "$cc" $CFLAGS -o "$TMP/result" "$srcabs" -lm \
            || die "$EX_COMPILE" "компиляция '$src' завершилась с ошибкой"
        result=$TMP/result
        ;;
    cxx)
        cxx=$(find_tool "${CXX:-}" c++ g++ clang++) || die "$EX_NOTOOL" "не найден компилятор C++"
        run "$cxx" $CXXFLAGS -o "$TMP/result" "$srcabs" \
            || die "$EX_COMPILE" "компиляция '$src' завершилась с ошибкой"
        result=$TMP/result
        ;;
    tex)
        tex=$(find_tool "${TEX:-}" pdflatex xelatex lualatex) || die "$EX_NOTOOL" "не найден TeX-движок (pdflatex)"
        TEXINPUTS=$srcdir:$TEXINPUTS
        export TEXINPUTS
        for pass in 1 2; do
            run "$tex" -interaction=nonstopmode -halt-on-error \
                -output-directory="$TMP" -jobname=result "$srcabs" >"$TMP/tex-pass$pass.out" 2>&1 \
                || { cat "$TMP/tex-pass$pass.out" >&2
                     die "$EX_COMPILE" "TeX-сборка '$src' завершилась с ошибкой"; }
        done
        result=$TMP/result.pdf
        ;;
esac

[ -f "$result" ] || die "$EX_NORESULT" "сборка прошла, но результат не создан"

PARTIAL=$srcdir/$out
cp -f -- "$result" "$PARTIAL" || die "$EX_NORESULT" "не удалось записать '$PARTIAL'"
[ "$kind" = tex ] || chmod +x -- "$PARTIAL" 2>/dev/null
PARTIAL=

echo "Готово: $srcdir/$out"
exit 0
