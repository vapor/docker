build_and_tag () {
	REPO=$1
	TAG=$2
    echo "📦 Building vapor/$REPO:$TAG"
    docker tag $(docker build --no-cache -q -f $REPO/$TAG/Dockerfile .) vapor/$REPO:$TAG
    docker push vapor/$REPO:$TAG
}

build_and_tag "swift" "5.2"
build_and_tag "swift" "5.2-bionic"
build_and_tag "swift" "5.2-xenial"
build_and_tag "swift" "5.1"
build_and_tag "swift" "5.1-bionic"
build_and_tag "swift" "5.1-xenial"
build_and_tag "swift" "5.0"
build_and_tag "swift" "5.0-bionic"
build_and_tag "swift" "5.0-xenial"
build_and_tag "ubuntu" "18.04"
