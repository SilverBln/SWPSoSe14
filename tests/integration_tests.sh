#!/bin/bash

### Usage info
function show_help {
cat << EOF
Usage: ${0##*/} [-hvl] [-e/d TEST] [TEST]...
Without arguments the script runs all enabled tests.
When a test name is given then run this test.

-h         Display this help and exit
-e/d TEST  Enable/Diasble the specified test.
-l         List all tests and their status.
-r         Run all not enabled tests.
-v         Verbose mode. Can be used multiple times for increased
           verbotisty.
EOF
}

### Function for reading in-/output files
function readtest {
  unset STDIN
  unset STDOUT
  unset STDERR

  FILE=$1
  i=0
  # 0=STDIN, 1=STDOUT, 2=STDERR
  mode=0

  while read -r line; do
    if [ "$line" = "#" ]; then
      # Next test case OR the stdout/stderr section of a test case.
      if [ $mode -gt 0 ]; then
        # Next test case.
        i=$(($i + 1))
        mode=0
        continue
      fi

      # Else $mode is 0. This means we are now reading the
      # stdout/stderr section of a test case. It consists
      # of two sections (for stdout and stderr), delimited
      # by a line containg a single percent symbol (%). The second
      # section (for stderr) and its leading "percent symbol line"
      # are optional for backward compatibility.
      mode=1
      continue
    elif [ "$line" = "%" ]; then
      # Now comes the stderr section.
      mode=2
      continue
    fi

    # Else this is a normal input/output line.
    case "$mode" in
      0)
        STDIN[$i]="${STDIN[$i]}${line}"
        ;;
      1)
        STDOUT[$i]="${STDOUT[$i]}${line}"
        ;;
      2)
        STDERR[$i]="${STDERR[$i]}${line}"
        ;;
    esac
   done < "$FILE"

   UNIT_TESTCASES=$(($i + 1))
}

### Function to get the correct test name for a file.
function get_name {
  filename="${1##*/}"
  filename="${filename%%.*}"
  echo "$filename"
}

### Get the filename to a given test name
function get_filename {
  name="$1"
  echo "$TESTDIR/$name.rail"
}

### Function to run a single test
function run_one {
  dontrun=false
  filename=$(get_name "$1")

  if [ -f "$TESTDIR/$filename$EXT" ]
    then
      readtest "$TESTDIR/$filename$EXT"
    else
      fail=true
      echo -e "`$red`ERROR`$NC` testing: \"$filename.rail\". $EXT-file is missing."
      return
  fi

  errormsg=$(dist/build/SWPSoSe14/SWPSoSe14 -c -i "$1" -o "$TMPDIR/$filename.ll" 2>&1) \
    && llvm-link "$TMPDIR/$filename.ll" src/RailCompiler/stack.ll > "$TMPDIR/$filename" \
    && chmod +x "$TMPDIR/$filename" || {
      TOTAL_TESTCASES=$(($TOTAL_TESTCASES + 1))

      # Check STDOUT first for backward compatibility.
      if [[ "$errormsg" == "${STDOUT[0]}" || "$errormsg" == "${STDERR[0]}" ]]; then
        echo -e "`$green`Passed`$NC` expected fail \"$filename.rail\"."
      else
        fail=true
        echo -e "`$red`ERROR`$NC` compiling/linking \"$filename.rail\" with error: \"$errormsg\""
      fi

      return
  }

  # Create temporary files for stdout and stderr.
  stdoutfile=$(mktemp --tmpdir="$TMPDIR" swp14_ci_stdout.XXXXX)
  if [ $? -gt 0 ]; then
    echo -e "`$red`ERROR`$NC` testing: \"$filename.rail\". Could not create temporary file for stdout."
    fail=true
    return
  fi

  stderrfile=$(mktemp --tmpdir="$TMPDIR" swp14_ci_stderr.XXXXX)
  if [ $? -gt 0 ]; then
    echo -e "`$red`ERROR`$NC` testing: \"$filename.rail\". Could not create temporary file for stderr."
    fail=true
    return
  fi

  for i in $(seq 0 $(($UNIT_TESTCASES - 1))); do
    TOTAL_TESTCASES=$(($TOTAL_TESTCASES + 1))

    # Execute the test!
    echo -ne "${STDIN[$i]}" | do_lli "$TMPDIR/$filename" 1>"$stdoutfile" 2>"$stderrfile"

    # Read stdout and stderr, while converting all actual newlines to \n.
    # Really ugly: bash command substitution eats trailing newlines so we
    # need to add a terminating character and then remove it again.
    stdout=$(cat "$stdoutfile"; echo x)
    stdout=${stdout%x}
    stdout=${stdout//$'\n'/\\n}

    stderr=$(cat "$stderrfile"; echo x)
    stderr=${stderr%x}
    stderr=${stderr//$'\n'/\\n}

    if [[ "$stdout" == "${STDOUT[$i]}" && "$stderr" == "${STDERR[$i]}" ]]; then
      echo "`$green`Passed`$NC` \"$filename.rail\" with input \"${STDIN[$i]}\""
    else
      fail=true
      echo "`$red`ERROR`$NC` testing \"$filename.rail\" with input \"${STDIN[$i]}\"!" \
        "Expected \"${STDOUT[$i]}\" on stdin, got \"$stdout\";" \
        "expected \"${STDERR[$i]}\" on stderr, got \"$stderr\"."
    fi
  done
}

### Function to compile and run all .rail files
function run_all {
  for f in "$TESTDIR"/*.rail; do
    if [ "$reverse" = true ]; then
      if [ ! -f "$TESTDIR/run/$(get_name "$f").rail" ]; then 
        run_one "$f"
      fi
    else
      run_one "$f"
    fi
  done
}

### Function to correctly call the LLVM interpreter
function do_lli {
  # On some platforms, the LLVM IR interpreter is not called "lli", but
  # something like "lli-x.y", where x.y is the LLVM version -- there may be
  # multiple such binaries for different LLVM versions.
  # Instead of trying to find the right version, we currently assume that
  # such platforms use binfmt_misc to execute LLVM IR files directly (e. g. Ubuntu).
  if command -v lli >/dev/null; then
      lli "$@"
  else
      "$@"
  fi
}


### Directory magic, so our cwd is the project home directory.
OLDDIR=$(pwd)
unset CDPATH
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
cd "$DIR/.."

### Define Terminal Colours
red="eval tput setaf 1; tput bold"
green="eval tput setaf 2; tput bold"
NC="tput sgr 0" # No Color

### Parse commandline options.
verbose=0
test=""
enable=""
disable=""

OPTIND=1
while getopts "hvlre:d:" opt; do
  case "$opt" in
    h)
      show_help
      exit 0
      ;;
    v)
      verbose=$(($verbose + 1))
      ;;
    l)
      list=true
      ;;
    r)
      reverse=true
      ;;
    e)
      enable=$OPTARG
      ;;
    d)
      disable=$OPTARG
      ;;
    '?')
      show_help >&2
      exit 1
      ;;
  esac
done
shift "$((OPTIND-1))" # Shift off the options and optional --.
test="$1"

### Checking for incompatible options.
count=0
[[ -n $list ]] && count=$(($count + 1))
[[ -n "$disable" ]] && count=$(($count + 1))
[[ -n "$enable" ]] && count=$(($count + 1))
if (( $count > 1 )); then
  echo "Only specify one of -l, -e, -d."
  exit 1
fi

### Main function.
TOTAL_TESTCASES=0

if [ "$reverse" = true ]; then
  TESTDIR="integration-tests"
else
  TESTDIR="integration-tests/run"
fi
EXT=".io"
if [ -n "$disable" ];then
  rm "$TESTDIR"/"$disable".{rail,io}
  exit 0
fi
if [ -n "$enable" ];then
  ln -s -t "$TESTDIR" ../$enable.{rail,io}
  exit 0
fi
if [ -n "$list" ]; then
  echo -ne "`$green`Tests to run:`$NC`\n\n"
  for file in "$TESTDIR"/*.rail;do
    echo $(get_name $file)
  done
  echo -ne "\n\n`$red`Disabled tests:`$NC`\n\n"
  for file in "$TESTDIR"/../*.rail;do
    if [ ! -f "$TESTDIR"/`basename "$file"` ];then
      echo $(get_name $file)
    fi
  done
  exit 0
fi

TMPDIR=tests/tmp
mkdir -p $TMPDIR
fail=false
if [ -n "$test" ];then
  if [ "${test##*.}" == "rail" ]; then
    # Set the TESTDIR to the directory the .rail file is in.
    test="$OLDDIR"/"$test"
    TESTDIR=${test%/*}
  else
    TESTDIR="integration-tests"
    test=$(get_filename "$test") # Find the path to the specified test
  fi
  if [ -f "$test" ]; then
    run_one "$test"
  else
    echo "`$red`ERROR:`$NC` Test $test not found."
  fi
else
  run_all
fi
rm -r tests/tmp

echo
echo "RAN $TOTAL_TESTCASES TESTCASES IN TOTAL."


### DEBUGGING:
function debugprint {
echo "STDIN"
for e in "${STDIN[@]}";do
  echo "$e"
done

echo "STDOUT"
for e in "${STDOUT[@]}";do
  echo "$e"
done

echo "STDERR"
for e in "${STDERR[@]}";do
  echo "$e"
done
}

#debugprint

if [ "$fail" = true ];then
  exit 1
fi

# vim:ts=2 sw=2 et
