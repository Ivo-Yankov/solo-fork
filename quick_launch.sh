npm install -g @hashgraph/solo@0.38.0

export SOLO_CLUSTER_NAME=solo-e2e
export SOLO_NAMESPACE=solo-e2e
export SOLO_CLUSTER_SETUP_NAMESPACE=solo-setup
export SOLO_DEPLOYMENT=solo-e2e

kind delete cluster -n "${SOLO_CLUSTER_NAME}"
kind create cluster -n "${SOLO_CLUSTER_NAME}"

rm -rf ~/.solo/local-config.yaml

solo init
solo cluster-ref setup -s "${SOLO_CLUSTER_SETUP_NAMESPACE}"
solo cluster-ref connect --cluster-ref kind-${SOLO_CLUSTER_NAME} --context kind-${SOLO_CLUSTER_NAME}

solo deployment create -n "${SOLO_NAMESPACE}" --deployment "${SOLO_DEPLOYMENT}"

solo deployment add-cluster --deployment "${SOLO_DEPLOYMENT}" --cluster-ref kind-${SOLO_CLUSTER_NAME} --num-consensus-nodes 2

solo node keys --gossip-keys --tls-keys -i node1,node2 --deployment "${SOLO_DEPLOYMENT}"

solo network deploy --deployment "${SOLO_DEPLOYMENT}" -i node1,node2

solo node setup -i node1,node2 --deployment "${SOLO_DEPLOYMENT}"
solo node start -i node1,node2 --deployment "${SOLO_DEPLOYMENT}"

kubectl port-forward -n "${SOLO_CLUSTER_NAME}" svc/haproxy-node1-svc 50211:50211 &

solo account create --deployment "${SOLO_DEPLOYMENT}" --hbar-amount 100 --set-alias > test.log
export OPERATOR_ID=$(grep "accountId" test.log | awk '{print $2}' | sed 's/"//g'| sed 's/,//g')
echo "OPERATOR_ID=${OPERATOR_ID}"

solo account get --deployment "${SOLO_DEPLOYMENT}" --account-id "${OPERATOR_ID}" --private-key > test.log
export OPERATOR_KEY=$(grep "privateKey" test.log | grep -v "privateKeyRaw" | awk '{print $2}' | sed 's/"//g'| sed 's/,//g')
echo "OPERATOR_KEY=${OPERATOR_KEY}"

#git clone https://github.com/hiero-ledger/hiero-sdk-js.git
cd /Users/jeffrey/hiero-sdk-js
npx vitest --config=test/vitest-node-integration.config.ts ScheduleCreateIntegrationTest.js

