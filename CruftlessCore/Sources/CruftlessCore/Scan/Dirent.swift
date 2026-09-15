import Darwin

public enum Dirent: Sendable {
    public static func name(of entry: UnsafeMutablePointer<dirent>) -> String? {
        withUnsafeBytes(of: entry.pointee.d_name) { ptr -> String? in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                return nil
            }
            return String(cString: base)
        }
    }
}
