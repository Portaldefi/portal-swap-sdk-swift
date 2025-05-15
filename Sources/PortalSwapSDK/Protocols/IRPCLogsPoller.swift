protocol IRPCLogsPoller {
    func watchContractEvents(interval: TimeInterval, onLogs: @escaping ([EthereumLogObject]) -> Void, onError: @escaping (Error) -> Void)
    func stopWatchingContractEvents()
}
