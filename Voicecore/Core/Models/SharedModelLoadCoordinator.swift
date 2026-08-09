// SharedModelLoadCoordinator.swift
// Coalesces concurrent load requests for the same model key into a single in-flight task.

import Foundation

private struct SharedModelLoadValue: @unchecked Sendable {
    let value: Any
}

private struct SharedModelLoadEntry {
    let generation: UUID
    let task: Task<SharedModelLoadValue, Error>
    var waiterIDs: Set<UUID>
}

struct SharedModelLoadTask: Sendable {
    fileprivate let task: Task<SharedModelLoadValue, Error>

    func waitForCompletion() async {
        _ = try? await task.value
    }
}

@MainActor
private final class SharedModelLoadStorage {
    private var entries: [String: SharedModelLoadEntry] = [:]

    var hasPendingLoad: Bool { !entries.isEmpty }

    func value<Value: Sendable>(
        for key: String,
        start: @escaping @Sendable () async throws -> Value
    ) async throws -> SharedModelLoadValue {
        let waiterID = UUID()
        let generation: UUID
        let task: Task<SharedModelLoadValue, Error>
        if var entry = entries[key] {
            entry.waiterIDs.insert(waiterID)
            entries[key] = entry
            generation = entry.generation
            task = entry.task
        } else {
            generation = UUID()
            task = Task {
                SharedModelLoadValue(value: try await start())
            }
            entries[key] = SharedModelLoadEntry(
                generation: generation,
                task: task,
                waiterIDs: [waiterID]
            )
        }

        let coordinator = self
        return try await withTaskCancellationHandler {
            defer { finishWaiter(waiterID, key: key, generation: generation) }
            let value = try await task.value
            try Task.checkCancellation()
            guard entries[key]?.generation == generation else {
                throw CancellationError()
            }
            return value
        } onCancel: {
            Task { @MainActor in
                coordinator.cancelWaiter(waiterID, key: key, generation: generation)
            }
        }
    }

    @discardableResult
    func cancelAll() -> [SharedModelLoadTask] {
        let tasks = entries.values.map { SharedModelLoadTask(task: $0.task) }
        entries.removeAll()
        for task in tasks {
            task.task.cancel()
        }
        return tasks
    }

    private func cancelWaiter(_ waiterID: UUID, key: String, generation: UUID) {
        guard var entry = entries[key],
              entry.generation == generation,
              entry.waiterIDs.remove(waiterID) != nil
        else { return }

        if entry.waiterIDs.isEmpty {
            entries[key] = nil
            entry.task.cancel()
        } else {
            entries[key] = entry
        }
    }

    private func finishWaiter(_ waiterID: UUID, key: String, generation: UUID) {
        guard var entry = entries[key],
              entry.generation == generation,
              entry.waiterIDs.remove(waiterID) != nil
        else { return }

        entries[key] = entry.waiterIDs.isEmpty ? nil : entry
    }
}

@MainActor
struct SharedModelLoadCoordinator<Value: Sendable> {
    private let storage = SharedModelLoadStorage()

    var hasPendingLoad: Bool { storage.hasPendingLoad }

    func value(
        for key: String,
        start: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let loadedValue = try await storage.value(for: key, start: start)
        return loadedValue.value as! Value
    }

    @discardableResult
    func cancelAll() -> [SharedModelLoadTask] {
        storage.cancelAll()
    }
}

extension FileManager {
    func directoryContainsRegularFiles(at url: URL) -> Bool {
        guard let enumerator = self.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                return true
            }
        }
        return false
    }

    func allocatedSizeOfDirectory(at url: URL) throws -> UInt64 {
        var totalSize: UInt64 = 0
        let enumerator = self.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            totalSize += UInt64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0)
        }
        return totalSize
    }
}
