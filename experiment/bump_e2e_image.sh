#!/usr/bin/env bash
# Copyright 2017 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Usage: bump_e2e_image.sh

set -o errexit
set -o nounset
set -o pipefail

dirty="$(git status --porcelain)"
if [[ -n ${dirty} ]]; then
  echo "Tree not clean:"
  echo "${dirty}"
  exit 1
fi

TREE="$(dirname ${BASH_SOURCE[0]})/.."

DATE="$(date +v%Y%m%d)"
TAG="${DATE}-$(git describe --tags --always --dirty)"
pushd "${TREE}/images/kubekins-e2e"
make push
K8S=1.9 make push
K8S=1.8 make push
K8S=1.7 make push
K8S=1.6 make push
popd

echo "TAG = ${TAG}"

sed -i "s/DEFAULT_KUBEKINS_TAG = '.*'/DEFAULT_KUBEKINS_TAG = '${TAG}-master'/" "${TREE}/scenarios/kubernetes_e2e.py"
sed -i "s/\/kubekins-e2e:.*$/\/kubekins-e2e:${TAG}-master/" "${TREE}/images/kubeadm/Dockerfile"
sed -i "s/\/kubekins-e2e:v.*$/\/kubekins-e2e:${TAG}-master/" "${TREE}/experiment/generate_tests.py"
sed -i "s/\/kubekins-e2e:v.*-\(.*\)$/\/kubekins-e2e:${TAG}-\1/" "${TREE}/experiment/test_config.yaml"

pushd "${TREE}"
bazel run //experiment:generate_tests -- \
  --yaml-config-path=experiment/test_config.yaml \
  --json-config-path=jobs/config.json \
  --prow-config-path=prow/config.yaml
bazel run //jobs:config_sort
popd

# Scan for kubekins-e2e:v.* as a rudimentary way to avoid
# replacing :latest.
sed -i "s/\/kubekins-e2e:v.*-\(.*\)$/\/kubekins-e2e:${TAG}-\1/" "${TREE}/prow/config.yaml"
git commit -am "Bump to gcr.io/k8s-testimages/kubekins-e2e:${TAG}-(master|releases) (using generate_tests and manual)"

# Bump kubeadm image

TAG="${DATE}-$(git describe --tags --always --dirty)"
pushd "${TREE}/images/kubeadm"
make push TAG="${TAG}"
popd

sed -i "s/\/e2e-kubeadm:v.*$/\/e2e-kubeadm:${TAG}/" "${TREE}/prow/config.yaml"
git commit -am "Bump to e2e-kubeadm:${TAG}"
