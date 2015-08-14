#!/usr/bin/env bash

DEPS=$(cat)

while read -r SCC
do
    echo "Next SCC" >> /dev/stderr
    while read -r ID
    do
        # TODO: Make this a more generic sub-set relation
        NAME=$(echo "$ID" | jq -r '.name')
        MOD=$( echo "$ID" | jq -r '.module')
        PKG=$( echo "$ID" | jq -r '.package')
        COND='.name == $name and .module == $mod and .package == $pkg'

        echo "Marking '$ID' for clustering" >> /dev/stderr
        DEPS=$(echo "$DEPS" | jq \
            --arg name "$NAME"   \
            --arg mod  "$MOD"    \
            --arg pkg  "$PKG"    \
            "map(if $COND then (. + {\"tocluster\": true}) else . end)")
    done < <(echo "$SCC" | jq -c '.[]')

    # Update all features with the latest clusters

    # Look up an ID in $deps
    COND2='.name == $this.name and .module == $this.module and .package == $this.package'
    LOOKUP='(. as $this | $deps | map(select('"$COND2"') | .cluster) | . + [0] | .[0] | . + 300)'
    FEATURES="(.features | map(if type == \"object\" then ($LOOKUP) else . end))"

    # Cluster. We call runWeka.sh directly since nix-shell adds a lot of
    # overhead, which we move outside the loop to our own invocation
    echo "Clustering..." >> /dev/stderr
    CLUSTERED=$(
        echo "$DEPS" |
        jq '. as $deps | $deps | map(. + {"features": '"$FEATURES"'})' |
        ./runWeka.sh)

    # Add new clusters to DEPS
    echo "Collating..." >> /dev/stderr
    DEPS=$(echo "$DEPS" | jq --argfile clustered <(echo "$CLUSTERED") \
                             'map(. as $this | $clustered | map(select(.name == $this.name and .module == $this.module and .package == $this.package)) | map(.cluster) | if length == 1 then $this + {"cluster": .[0]} else $this end)')
done < <(echo "$DEPS" | order-deps | jq -c '.[]')

echo "Done" >> /dev/stderr
echo "$DEPS"