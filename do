#!/bin/bash

ROOT=$(dirname $(realpath $BASH_SOURCE[0]))

[ $# -eq 0 ] && {
  ./do --tasks
  ./do --tasks_csc
  exit 0
}

if [ "$1" == "clean" ]; then
  ${ROOT}/bin/clean
  exit $?
fi


source $ROOT/bin/setup

rakefile_name=

for arg; do
  case "$arg" in
    *isa_explorer* | *proc_crd* | *proc_ctp* | *profile* | *Profile* | RVI* | RVA* | RVB* | RVM* | *csc*)
      [ "$arg" == "--tasks_csc" ] && {
        arg="--tasks"
      }

      [ "$rakefile_name" == "Rakefile" ] && {
        echo "Can't mix CSC and non-CSC tasks"
        exit 1
      }
      rakefile_name="Rakefile_csc"
      ;;
    *)
      [ "$rakefile_name" == "Rakefile_csc" ] && {
        echo "Can't mix CSC and non-CSC tasks"
        exit 1
      }
      rakefile_name="Rakefile"
        ;;
  esac

  args+="$arg"
done

echo "Using $rakefile_name"

# really long way of invoking rake, but renamed to 'do'
$BUNDLE exec --gemfile $ROOT/Gemfile ruby -r rake -e "Rake.application.init('do', ARGV.append('--rakefile=$rakefile_name'));Rake.application.load_rakefile;Rake.application.top_level" -- $args
