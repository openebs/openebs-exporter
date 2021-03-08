#!/bin/bash

# Copyright 2020 The OpenEBS Authors
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
#
set -e

if [ -z ${DIMAGE} ];
then
  echo "Error: DIMAGE is not specified";
  exit 1
fi

function pushBuildx() {
  BUILD_TAG="latest"
  TARGET_IMG=${DIMAGE}

# TODO Currently ci builds with commit tag will not be generated,
# since buildx does not support multiple repo
  # if not a release build set the tag and ci image
  if [ -z "${RELEASE_TAG}" ]; then
    return
#    BUILD_ID=$(git describe --tags --always)
#    BUILD_TAG="${BRANCH}-${BUILD_ID}"
#    TARGET_IMG="${DIMAGE}-ci"
  fi

  echo "Tagging and pushing ${DIMAGE}:${TAG} as ${TARGET_IMG}:${BUILD_TAG}"
  docker buildx imagetools create "${DIMAGE}:${TAG}" -t "${TARGET_IMG}:${BUILD_TAG}"
}

# if the push is for a buildx build
if [[ ${BUILDX} ]]; then
  pushBuildx
  exit 0
fi

# The below steps are required for pushing arch specific images.
# This steps will be removed eventually in favour of buildx-push
IMAGEID=$( sudo docker images -q "${DIMAGE}:ci" )
echo "${DIMAGE}:ci -> $IMAGEID"
if [ -z "${IMAGEID}" ];
then
  echo "Error: unable to get IMAGEID for ${DIMAGE}:ci";
  exit 1
fi


# Generate a unique tag based on the commit and tag
BUILD_ID=$(git describe --tags --always)

# Determine the current branch
CURRENT_BRANCH=""
if [ -z ${BRANCH} ];
then
  CURRENT_BRANCH=$(git branch | grep \* | cut -d ' ' -f2)
else
  CURRENT_BRANCH=${BRANCH}
fi

#Depending on the branch where builds are generated,
# set the tag CI (fixed) and build tags.
BUILD_TAG="${CURRENT_BRANCH}-${BUILD_ID}"
CI_TAG="${CURRENT_BRANCH}-ci"
if [ ${CURRENT_BRANCH} = "develop" ]; then
  CI_TAG="ci"
fi

echo "Set the fixed ci image tag as: ${CI_TAG}"
echo "Set the build/unique image tag as: ${BUILD_TAG}"

function TagAndPushImage() {
  REPO="$1"
  # Trim the `v` from the TAG if it exists
  # Example: v1.10.0 maps to 1.10.0
  # Example: 1.10.0 maps to 1.10.0
  # Example: v1.10.0-custom maps to 1.10.0-custom
  TAG="${2#v}"

  #Add an option to specify a custom TAG_SUFFIX
  #via environment variable. Default is no tag.
  #Example suffix could be "-debug" of "-dev"
  IMAGE_URI="${REPO}:${TAG}${TAG_SUFFIX}";
  sudo docker tag ${IMAGEID} ${IMAGE_URI};
  echo " push ${IMAGE_URI}";
  sudo docker push ${IMAGE_URI};
}


if [ ! -z "${DNAME}" ] && [ ! -z "${DPASS}" ];
then
  sudo docker login -u "${DNAME}" -p "${DPASS}";

  # Push CI tagged image - :ci or :branch-ci
  TagAndPushImage "${DIMAGE}" "${CI_TAG}"

  # Push unique tagged image - :master-<uuid> or :branch-<uuid>
  # This unique/build image will be pushed to corresponding ci repo.
  TagAndPushImage "${DIMAGE}-ci" "${BUILD_TAG}"

  if [ ! -z "${RELEASE_TAG}" ] ;
  then
    # Push with different tags if tagged as a release
    # When github is tagged with a release, then github actions release workflow will
    # set the release tag in env RELEASE_TAG
    TagAndPushImage "${DIMAGE}" "${RELEASE_TAG}"
    TagAndPushImage "${DIMAGE}" "latest"
  fi;
else
  echo "No docker credentials provided. Skip uploading ${DIMAGE} to docker hub";
fi;

# Push ci image to quay.io for security scanning
if [ ! -z "${QNAME}" ] && [ ! -z "${QPASS}" ];
then
  sudo docker login -u "${QNAME}" -p "${QPASS}" quay.io;

  # Push CI tagged image - :ci or :branch-ci
  TagAndPushImage "quay.io/${DIMAGE}" "${CI_TAG}"

  if [ ! -z "${RELEASE_TAG}" ] ;
  then
    # Push with different tags if tagged as a release
    # When github is tagged with a release, then github actions release workflow will
    # set the release tag in env RELEASE_TAG
    # Trim the `v` from the RELEASE_TAG if it exists
    TagAndPushImage "quay.io/${DIMAGE}" "${RELEASE_TAG}"
    TagAndPushImage "quay.io/${DIMAGE}" "latest"
  fi;
else
  echo "No docker credentials provided. Skip uploading ${DIMAGE} to quay";
fi;

