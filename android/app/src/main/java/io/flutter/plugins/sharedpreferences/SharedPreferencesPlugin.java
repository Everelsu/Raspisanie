package io.flutter.plugins.sharedpreferences;

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * Compatibility shim for projects where GeneratedPluginRegistrant references
 * SharedPreferencesPlugin, but only LegacySharedPreferencesPlugin is available
 * on the classpath during Java compilation.
 */
public final class SharedPreferencesPlugin implements FlutterPlugin {
  private final LegacySharedPreferencesPlugin delegate = new LegacySharedPreferencesPlugin();

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    delegate.onAttachedToEngine(binding);
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    delegate.onDetachedFromEngine(binding);
  }
}
