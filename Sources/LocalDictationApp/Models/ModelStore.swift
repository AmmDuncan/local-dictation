import Foundation

/// The whisper transcription model store — download/verify/select machinery is
/// inherited from `CatalogModelStore`; this just binds it to the whisper catalog
/// and the `modelPath` setting.
@MainActor
final class ModelStore: CatalogModelStore {
    init() {
        super.init(catalog: ModelCatalog.all, activePathKey: AppSettingsKeys.modelPath)
    }
}
