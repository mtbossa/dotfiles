function composer_install_docker() {
  docker run --rm \
    -u "$(id -u):$(id -g)" \
    -v "$(pwd):/var/www/html" \
    -w /var/www/html \
    laravelsail/php${1:-83}-composer:latest \
    composer install --ignore-platform-reqs
}
