function dka() {
  docker kill $(docker ps -q)
}
