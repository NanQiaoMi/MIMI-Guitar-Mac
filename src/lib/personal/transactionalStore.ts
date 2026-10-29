/**
 * Transactional Store Wrapper for IndexedDB
 * Ensures atomic operations with version chain and rollback support
 */

export interface TransactionOptions {
  maxRetries?: number;
  timeout?: number;
}

export interface VersionedData<T> {
  version: number;
  timestamp: number;
  checksum: string;
  data: T;
}

export class TransactionalStore<T> {
  private dbName: string;
  private storeName: string;
  private maxVersions = 3;

  constructor(dbName: string, storeName: string) {
    this.dbName = dbName;
    this.storeName = storeName;
  }

  async write(key: string, data: T, options: TransactionOptions = {}): Promise<boolean> {
    const { maxRetries = 3, timeout = 5000 } = options;

    for (let attempt = 0; attempt < maxRetries; attempt++) {
      try {
        return await this.attemptWrite(key, data, timeout);
      } catch (error) {
        if (this.isQuotaError(error) && attempt < maxRetries - 1) {
          await this.cleanupOldVersions(key);
          continue;
        }
        console.error(`[TransactionalStore] Write failed (attempt ${attempt + 1}):`, error);
        if (attempt === maxRetries - 1) return false;
      }
    }
    return false;
  }

  private async attemptWrite(key: string, data: T, timeout: number): Promise<boolean> {
    const db = await this.openDB();

    return new Promise<boolean>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Write timeout')), timeout);

      const transaction = db.transaction([this.storeName], 'readwrite');
      const store = transaction.objectStore(this.storeName);

      transaction.oncomplete = () => {
        clearTimeout(timer);
        db.close();
        resolve(true);
      };

      transaction.onerror = () => {
        clearTimeout(timer);
        db.close();
        reject(transaction.error);
      };

      transaction.onabort = () => {
        clearTimeout(timer);
        db.close();
        reject(new Error('Transaction aborted'));
      };

      // Read current versions
      const getRequest = store.get(key);
      getRequest.onsuccess = () => {
        const existing = getRequest.result as VersionedData<T>[] | undefined;
        const versions = existing || [];

        const newVersion: VersionedData<T> = {
          version: versions.length > 0 ? versions[versions.length - 1].version + 1 : 1,
          timestamp: Date.now(),
          checksum: this.calculateChecksum(data),
          data,
        };

        // Keep only last N versions
        const updatedVersions = [...versions, newVersion].slice(-this.maxVersions);

        store.put(updatedVersions, key);
      };

      getRequest.onerror = () => {
        clearTimeout(timer);
        reject(getRequest.error);
      };
    });
  }

  async read(key: string): Promise<T | null> {
    const db = await this.openDB();

    return new Promise<T | null>((resolve, reject) => {
      const transaction = db.transaction([this.storeName], 'readonly');
      const store = transaction.objectStore(this.storeName);
      const request = store.get(key);

      request.onsuccess = () => {
        db.close();
        const versions = request.result as VersionedData<T>[] | undefined;

        if (!versions || versions.length === 0) {
          resolve(null);
          return;
        }

        // Try versions from newest to oldest
        for (let i = versions.length - 1; i >= 0; i--) {
          const version = versions[i];
          const actualChecksum = this.calculateChecksum(version.data);

          if (actualChecksum === version.checksum) {
            resolve(version.data);
            return;
          }

          console.warn(`[TransactionalStore] Corrupted version ${version.version}, trying older version`);
        }

        console.error('[TransactionalStore] All versions corrupted');
        resolve(null);
      };

      request.onerror = () => {
        db.close();
        reject(request.error);
      };
    });
  }

  private async cleanupOldVersions(key: string): Promise<void> {
    const db = await this.openDB();

    return new Promise<void>((resolve, reject) => {
      const transaction = db.transaction([this.storeName], 'readwrite');
      const store = transaction.objectStore(this.storeName);

      const request = store.get(key);
      request.onsuccess = () => {
        const versions = request.result as VersionedData<T>[] | undefined;

        if (versions && versions.length > 1) {
          // Keep only the latest version when cleaning up
          const latest = versions[versions.length - 1];
          store.put([latest], key);
        }

        db.close();
        resolve();
      };

      request.onerror = () => {
        db.close();
        reject(request.error);
      };
    });
  }

  private async openDB(): Promise<IDBDatabase> {
    return new Promise<IDBDatabase>((resolve, reject) => {
      const request = indexedDB.open(this.dbName, 1);

      request.onupgradeneeded = (event) => {
        const db = (event.target as IDBOpenDBRequest).result;
        if (!db.objectStoreNames.contains(this.storeName)) {
          db.createObjectStore(this.storeName);
        }
      };

      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  private isQuotaError(error: unknown): boolean {
    if (!error) return false;
    const message = String(error);
    return message.includes('QuotaExceededError') ||
           message.includes('quota') ||
           message.includes('storage');
  }

  private calculateChecksum(data: T): string {
    const str = JSON.stringify(data);
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      const char = str.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash;
    }
    return hash.toString(36);
  }
}
