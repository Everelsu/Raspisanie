export function isOnline(): boolean {
  if (typeof window === 'undefined') {
    return true;
  }
  
  return navigator.onLine;
}

export function addOnlineListener(callback: () => void): () => void {
  if (typeof window === 'undefined') {
    return () => {};
  }
  
  window.addEventListener('online', callback);
  
  return () => {
    window.removeEventListener('online', callback);
  };
}

export function addOfflineListener(callback: () => void): () => void {
  if (typeof window === 'undefined') {
    return () => {};
  }
  
  window.addEventListener('offline', callback);
  
  return () => {
    window.removeEventListener('offline', callback);
  };
}



