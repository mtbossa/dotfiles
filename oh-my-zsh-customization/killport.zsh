function killport() {
  kill -9 $(lsof -t -i:${1})
}
