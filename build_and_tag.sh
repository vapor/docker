build_and_tag () {
    echo "📦 Building Swift $1 on Ubuntu $2 at vapor/swift:$3"
    docker tag $(docker build -q -f $1/ubuntu/$2/Dockerfile .) vapor/swift:$3
    docker push vapor/swift:$3
}

build_and_tag "5.1" "18.04" "5.1"
build_and_tag "5.1" "18.04" "5.1-bionic"
build_and_tag "5.1" "16.04" "5.1-xenial"
build_and_tag "5.0" "18.04" "5.0"
build_and_tag "5.0" "18.04" "5.0-bionic"
build_and_tag "5.0" "16.04" "5.0-xenial"
