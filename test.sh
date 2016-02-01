#! /usr/bin/env nix-shell
#! nix-shell -i bash -p bash cabal2db annotatedb jq

BASE=$(dirname "$0")

# Assertion functions

function fail {
    # Unconditional failure
    [[ "$#" -eq 0 ]] || echo "FAIL $*"
    CODE=1
    return 1
}

function assertNotEmpty {
    # Fails if stdin is empty
    COUNT=$(grep -c "^")
    [[ "$COUNT" -gt 0 ]] || fail "$1"
}

# Look up tests from the environment

function getFunctions {
    # Get a list of the functions in this script
    declare -F | cut -d ' ' -f 3-
}

function getPkgTests {
    # Get a list of test functions which require a package
    getFunctions | grep '^pkgTest'
}

function getTests {
    # Get a list of all test functions
    getFunctions | grep '^test'
    # Apply each package test to each package
    while read -r pkg
    do
        while read -r test
        do
            echo "$test $pkg"
        done < <(getPkgTests)
    done < <(getTestPkgs)
}

function getTestPkgs {
    # A list of packages to test with
    cat <<EOF
list-extras
EOF
    #xmonad
    #pandoc
    #git-annex
    #hakyll
    #egison
    #lens
    #warp
    #conduit
    #ghc-mod
    #shelly
    #http-conduit
    #yesod-core
}

# Data generators

function getRawAsts {
    F="test-data/$1.rawasts"
    [[ ! -e "$F" ]] &&
        dump-hackage "$1" > "$F"
    cat "$F"
}

function getAsts {
    F="test-data/$1.asts"
    [[ ! -e "$F" ]] &&
        getRawAsts "$1" | annotateDb "$1" > "$F"
    cat "$F"
}

function getFeatures {
    F="test-data/$1.features"
    [[ ! -e "$F" ]] &&
        getAsts "$1" | "$BASE/extractFeatures.sh" > "$F"
    cat "$F"
}

function getClusters {
    [[ -z "$CLUSTERS" ]] && CLUSTERS=4
    export CLUSTERS
    F="test-data/$1.clusters.$CLUSTERS"
    [[ ! -e "$F" ]] &&
        getFeatures "$1" | "$BASE/nix_recurrentClustering.sh" > "$F"
    cat "$F"
}

# Tests

function pkgTestGetFeatures {
    getFeatures "$1" | assertNotEmpty "Couldn't get features from '$1'"
}

function pkgTestFeaturesConform {
    FEATURELENGTHS=$(getFeatures "$1" | jq -r '.[] | .features | length')
    COUNT=$(echo "$FEATURELENGTHS" | head -n 1)
    echo "$FEATURELENGTHS" | while read -r LINE
    do
        if [[ "$LINE" -ne "$COUNT" ]]
        then
            fail "Found '$LINE' features, was expecting '$COUNT'"
        fi
    done
}

function pkgTestAllClustered {
    for CLUSTERS in 1 2 3 5 7 11
    do
        if getClusters "$1" | jq '.[] | .tocluster' | grep "false" > /dev/null
        then
            fail "Clustering '$1' into '$CLUSTERS' clusters didn't include everything"
        fi
    done
}

function pkgTestHaveAllClusters {
    for CLUSTERS in 1 2 3 5 7 11
    do
        FOUND=$(getClusters "$1" | jq '.[] | .cluster')
        for NUM in $(seq 1 "$CLUSTERS")
        do
            echo "$FOUND" | grep "^${NUM}$" > /dev/null ||
                fail "Clustering '$1' into '$CLUSTERS' clusters, '$NUM' was empty"
        done
    done
}

function pkgTestClusterFields {
    for CLUSTERS in 1 2 3 5 7 11
    do
        for field in arity name module type package ast features cluster
        do
            RESULT=$(getClusters "$1" | jq "map(has(\"$field\")) | all")
            [[ "x$RESULT" = "xtrue" ]] ||
                fail "Clustering '$1' into '$CLUSTERS' clusters missed some '$field' entries"
        done
    done
}

# Test invocation

function traceTest {
    # Separate our stderr from the previous and give a timestamp
    echo -e "\n\n" >> /dev/stderr
    date           >> /dev/stderr

    # Always set -x to trace tests, but remember our previous setting
    OLDDEBUG=0
    [[ "$-" == *x* ]] && OLDDEBUG=1

    set -x
    export SHELLOPTS
    "$@"; PASS=$?

    # Disable -x if it wasn't set before
    [[ "$OLDDEBUG" -eq 0 ]] && set +x

    return "$PASS"
}

function runTest {
    # Log stderr in test-data/debug. On failure, send "FAIL" and the debug
    # path to stdout
    read -ra CMD <<<"$@" # Re-parse our args to split packages from functions
    PTH=$(echo "test-data/debug/$*" | sed 's/ /_/g')
    traceTest "${CMD[@]}" 2>> "$PTH" || fail "$* failed, see $PTH"
}

function runTests {
    # Overall script exit code
    CODE=0

    # Handle a regex, if we've been given one
    if [[ -z "$1" ]]
    then
        TESTS=$(getTests)
    else
        TESTS=$(getTests | grep "$1")
    fi

    while read -r test
    do
        # $test is either empty, successful or we're exiting with an error
        [[ -z "$test" ]] || runTest "$test" || CODE=1
    done < <(echo "$TESTS")
    return "$CODE"
}

mkdir -p test-data/debug
runTests "$1"