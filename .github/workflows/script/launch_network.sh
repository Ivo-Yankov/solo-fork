#!/bin/bash
set -eo pipefail

mirror_chart_path="${1}"

npm install -g @hashgraph/solo@0.35.2 --force
solo --version

export SOLO_CLUSTER_NAME=solo-e2e
export SOLO_NAMESPACE=solo-e2e
export SOLO_CLUSTER_SETUP_NAMESPACE=solo-setup
export SOLO_DEPLOYMENT=solo-e2e

kind delete cluster -n "${SOLO_CLUSTER_NAME}"
kind create cluster -n "${SOLO_CLUSTER_NAME}"

rm -rf ~/.solo/*

echo "**********************************"
echo " Deploy using old solo version"
echo "**********************************"


solo init
solo cluster setup -s "${SOLO_CLUSTER_SETUP_NAMESPACE}"
solo node keys --gossip-keys --tls-keys -i node1,node2
solo deployment create -i node1,node2 -n "${SOLO_NAMESPACE}" --context kind-"${SOLO_CLUSTER_NAME}" --email john@doe.com --deployment-clusters kind-"${SOLO_CLUSTER_NAME}" --cluster-ref kind-${SOLO_CLUSTER_NAME} --deployment "${SOLO_DEPLOYMENT}"

export CONSENSUS_NODE_VERSION=v0.58.10
# Use custom settings file for the deployment to avoid too many state saved in disk causing the no space left on device error
solo network deploy -i node1,node2 --deployment "${SOLO_DEPLOYMENT}" --pvcs --release-tag "${CONSENSUS_NODE_VERSION}" -q --settings-txt .github/workflows/support/v58-test/settings.txt
solo node setup -i node1,node2 --deployment "${SOLO_DEPLOYMENT}" --release-tag "${CONSENSUS_NODE_VERSION}" -q
solo node start -i node1,node2 --deployment "${SOLO_DEPLOYMENT}" -q
solo account create --deployment "${SOLO_DEPLOYMENT}" --hbar-amount 100

solo mirror-node deploy  --deployment "${SOLO_DEPLOYMENT}"

echo "**********************************"
echo " Migrate to new solo version"
echo "**********************************"


# trigger migration
npm run solo-test -- account create --deployment "${SOLO_DEPLOYMENT}"

# using new solo to redeploy solo deployment chart to new version
npm run solo-test -- node stop -i node1,node2 --deployment "${SOLO_DEPLOYMENT}"

npm run solo-test -- network deploy -i node1,node2 --deployment "${SOLO_DEPLOYMENT}" --pvcs --release-tag "${CONSENSUS_NODE_VERSION}" -q --settings-txt .github/workflows/support/v58-test/settings.txt

npm run solo-test -- node setup -i node1,node2 --deployment "${SOLO_DEPLOYMENT}" --release-tag "${CONSENSUS_NODE_VERSION}" -q
npm run solo-test -- node start -i node1,node2 --deployment "${SOLO_DEPLOYMENT}" -q

echo "**********************************"
echo " Upgrade mirror-node to newer version"
echo "**********************************"

npm run solo-test -- mirror-node deploy --deployment "${SOLO_DEPLOYMENT}" --cluster-ref kind-${SOLO_CLUSTER_NAME} --pinger -q --dev --chart-dir "${mirror_chart_path}"

echo "**********************************"
echo " Enable mirror test"
echo "**********************************"

helm upgrade mirror "${mirror_chart_path}"/hedera-mirror -n solo-e2e --reset-then-reuse-values --set test.enabled=true --set test.image.pullPolicy=Always --set test.image.tag=latest --set test.config.hiero.mirror.test.acceptance.network=OTHER  --set test.cucumberTags="@acceptance and not @schedulebase"

