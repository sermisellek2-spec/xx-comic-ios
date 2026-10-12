# 全需求入口与消费者对应表

按76个稳定ID定位当前生产消费者及检查引用，记录路径、方法和SHA。冻结Android引用只从696e80a Git对象读取。这里是静态追溯表，不是运行结果，不自动改变需求状态；同版本完整Apple及人工视觉仍待核对。

文字阅读/排版按用户要求移除，保留漫画导入及旧数据保护。SOURCE-02~04继续暂停；CONFIG-02与VERIFY-01仅通用配置/本机交互，不证明真实网站消费或认证通过。

| ID | 生产入口/消费者 | 对应检查 | 当前边界 |
| --- | --- | --- | --- |
| BASE-01 | build、release_product、NON_SOURCE_GATE | 综合门槛/范围核对 | 通过；实际结果另核对 |
| BASE-02 | build、release_product、NON_SOURCE_GATE | 综合门槛/范围核对 | 待核对；实际结果另核对 |
| BASE-03 | build、release_product、NON_SOURCE_GATE | 综合门槛/范围核对 | 待验收；实际结果另核对 |
| BASE-04 | build、release_product、NON_SOURCE_GATE | 综合门槛/范围核对 | 待验收；实际结果另核对 |
| BASE-05 | build、release_product、NON_SOURCE_GATE | 综合门槛/范围核对 | 待验收；实际结果另核对 |
| VIS-01 | AppThemeController、Palette、ThemeChoiceSheet、AppTheme | AppThemeTests、PreferencesTests、SettingsParityUITests、VisualMatrixUITests | 待验收；实际结果另核对 |
| VIS-02 | ParityIcon、RemoteImageView、BuiltinSourceCatalog | BuiltinSourceCatalogTests、CoverFallbackTests、AppNavigationTests、VisualMatrixUITests | 待验收；实际结果另核对 |
| VIS-03 | RootTabsViewController、ReaderChromeViews、AppTheme | AppThemeTests、RootTabGeometryTests、RootNavigationParityUITests、ReaderToolbarParityUITests、VisualMatrixUITests | 待验收；实际结果另核对 |
| VIS-04 | ComicGridViewController、DiscoverViewController、DetailViewController、RemoteImageView、BookshelfLayoutHelper、BookshelfReadingStatus | BookshelfReadingStatusTests、CoverFallbackTests、BookshelfParityUITests、VisualMatrixUITests | 待验收；实际结果另核对 |
| VIS-05 | ChapterDrawerSheet、ReaderSettingsViewController、SourceOptionScrollView、FilterDrawerNavigationController、ThemeChoiceSheet | SourceFilterSelectionTests、SourceDrawerTests、ReaderSettingsParityUITests、VisualMatrixUITests | 待验收；实际结果另核对 |
| VIS-06 | DetailFeedbackState、DetailViewController、RemoteImageView、SourceVerificationUI、ReaderLoadState、ComicDirectoryPreparation | ReaderLoadStateTests、ComicDirectoryPreparationTests、CoverFallbackTests、DetailFeedbackStateTests、CurrentParityUITests、Mh18VerificationTests | 待验收；实际结果另核对 |
| VIS-07 | RootTabsViewController、ThemeChoiceSheet、VolumeManagerViewController、ChapterDrawerSheet、AppTheme | AppThemeTests、RootTabGeometryTests、VisualMatrixUITests、RootNavigationParityUITests、VolumeManagerParityUITests | 待验收；实际结果另核对 |
| SHELF-01 | ComicGridViewController、BookshelfTabsView、BookshelfLayoutHelper | PreferencesTests、BookshelfParityUITests、VisualMatrixUITests | 待验收；实际结果另核对 |
| SHELF-02 | BookshelfGroupSheet、BookshelfGroupSelectSheet、ComicGridViewController、BookshelfGroupStore | BookshelfGroupStoreTests、BookshelfParityUITests | 待验收；实际结果另核对 |
| SHELF-03 | ComicGridViewController、LibraryStore | LibraryStoreTests、BookshelfParityUITests | 待验收；实际结果另核对 |
| SHELF-04 | ComicGridViewController、BookshelfResumeView、FavoriteUpdateChecker、FavoriteUpdateCoordinator、BookshelfReadingStatus、LibraryStore | FavoriteUpdateCheckerTests、FavoriteRevisionTests、BookshelfReadingStatusTests、LibraryStoreTests、BookshelfParityUITests、SettingsParityUITests | 待验收；实际结果另核对 |
| SHELF-05 | SourceSwitchSheet、AppEnvironment、ComicGridViewController、LibraryStore、ChapterMatching | LibraryStoreTests、ChapterMatchingTests、SourceReplacementTransactionTests、SourceSwitchParityUITests | 待验收；实际结果另核对 |
| SHELF-06 | FloatingImportBubble、ComicGridViewController、BatchImportSession、LocalImportPreparation | BatchImportSessionTests、LocalImportPreparationTests、BatchImportRecoveryUITests、EpubReadingUITests、ExternalFilesParityUITests | 待验收；实际结果另核对 |
| HISTORY-01 | ComicGridViewController、SettingsViewController、DiscoverViewController、LibraryStore | LibraryStoreTests、SettingsParityUITests、BookshelfParityUITests | 待验收；实际结果另核对 |
| DISC-01 | DiscoverViewController、SourceGroupSheet、AppEnvironment、SourceGroupStore、SourcePreferences | SourceGroupStoreTests、SourcePreferencesTests、SourceDrawerTests、SourceGroupsParityUITests、CurrentParityUITests | 待验收；实际结果另核对 |
| DISC-02 | DiscoverViewController、SearchRules | SearchRulesTests、SourceSearchTrimTests、CurrentParityUITests、VisualMatrixUITests | 待验收；实际结果另核对 |
| DISC-03 | DiscoverViewController、SearchRules | SearchRulesTests、SourceDrawerTests、CurrentParityUITests | 待验收；实际结果另核对 |
| DISC-04 | DiscoverViewController、SourceOptionScrollView、FilterDrawerNavigationController、SourceFilterSelection、DiscoveryHeaderGesture | SourceFilterSelectionTests、DiscoveryHeaderGestureTests、SourceDrawerTests、CurrentParityUITests、VisualMatrixUITests | 待验收；实际结果另核对 |
| DETAIL-01 | DetailViewController、DetailFeedbackState、RemoteImageView、ComicDirectoryPreparation、LibraryStore | ComicDirectoryPreparationTests、LibraryStoreTests、DetailFeedbackStateTests、CoverFallbackTests、CurrentParityUITests、VisualMatrixUITests | 待验收；实际结果另核对 |
| DETAIL-02 | SourceSwitchSheet、DetailViewController、AppEnvironment、SearchRules、ChapterMatching、ComicDirectoryPreparation | SearchRulesTests、ChapterMatchingTests、ComicDirectoryPreparationTests、SourceReplacementTransactionTests、SourceSwitchParityUITests | 待验收；实际结果另核对 |
| CONFIG-01 | SettingsViewController、ThemeChoiceSheet、ReaderSettingsViewController、ReaderPreferences、AppTheme | PreferencesTests、AppThemeTests、ImageEnhancementPolicyTests、SettingsParityUITests、ReaderSettingsParityUITests、AppNavigationTests | 待验收；实际结果另核对 |
| CONFIG-02 | AppEnvironment、SourceSettingsViewController、SourceGroupSheet、SourcePreferences、SourceConfigDocuments、PublicSourceRegistry | SourcePreferencesTests、SourceImportContractTests、SourceConfigDocumentsTests、RetiredComicSourceTests、BuiltinSourceRegistrationTests、SourceConfigFilesUITests、SourceGroupsParityUITests、SourceDrawerTests | 待核对；实际结果另核对 |
| CONFIG-03 | SourceSettingsViewController、SourceConfigDocuments、SourcePreferences | SourceConfigDocumentsTests、SourceImportContractTests、SourcePreferencesTests、SourceConfigFilesUITests | 待验收；实际结果另核对 |
| CONFIG-04 | CacheCleanupViewController、SettingsViewController、RemoteImageView、Mh18BrowserSession、HTTPResponseCache、StorageCalculator | CacheMaintenanceTests、CacheLateRestoreTests、CacheBackendContinuityTests、StorageCalculatorTests、CacheMaintenanceNativeTests、WebCacheCleanupTests、SettingsParityUITests、VisualMatrixUITests | 待验收；实际结果另核对 |
| CONFIG-05 | ErrorLogsViewController、SettingsViewController、ErrorLogStore、ErrorLogSanitizer | ErrorLogStoreTests、ErrorLogsParityUITests | 待验收；实际结果另核对 |
| CONFIG-06 | AboutAppViewController、SettingsViewController、AppUpdateChecker、IOSUpdatePolicy | AppUpdateCheckerTests、IOSUpdatePolicyTests、SettingsParityUITests | 待验收；实际结果另核对 |
| CONFIG-07 | SettingsViewController、SceneDelegate、AppEnvironment、UsageStatsClient | UsageStatsClientTests、UsageStatsReportingTests、SettingsParityUITests | 待验收；实际结果另核对 |
| READER-01 | ReaderViewController、ReaderPageLayout、ReaderSettingsViewController、ReaderPreferences、ReadingRules | PreferencesTests、ReadingRulesTests、ReaderMangaGeometryTests、ReaderSettingsParityUITests、ReaderContinuityUITests | 待验收；实际结果另核对 |
| READER-02 | ReaderViewController、ReaderPageLayout、ReadingRules | ReadingRulesTests、ReaderMangaGeometryTests、ReaderSettingsParityUITests、ReaderContinuityUITests | 待验收；实际结果另核对 |
| READER-03 | ReaderChromeViews、ReaderViewController、ReaderSession | ReaderSessionTests、ReaderToolbarParityUITests、ReaderContinuityUITests、VisualMatrixUITests | 待验收；实际结果另核对 |
| READER-04 | ReaderSeekBar、ReaderViewController、ReaderSeekSession | ReaderSeekSessionTests、ReaderSeekGeometryTests、ReaderContinuityUITests、ReaderToolbarParityUITests | 待验收；实际结果另核对 |
| READER-05 | ChapterDrawerSheet、ChapterFastScroller、ReaderViewController、ComicDirectoryPreparation、ChapterMatching | ComicDirectoryPreparationTests、ChapterMatchingTests、ReaderContinuityUITests、VisualMatrixUITests | 待验收；实际结果另核对 |
| READER-06 | ChapterDrawerSheet、ChapterFastScroller、ReaderViewController | ChapterMatchingTests、ReaderContinuityUITests | 待验收；实际结果另核对 |
| READER-07 | SourceSwitchSheet、ReaderViewController、DetailViewController、AppEnvironment、LibraryStore、ChapterMatching | LibraryStoreTests、ChapterMatchingTests、SourceReplacementTransactionTests、SourceSwitchParityUITests | 待验收；实际结果另核对 |
| READER-08 | ReaderViewController、ReaderPageLayout、SceneDelegate、ReaderSession、ReaderLoadState、LibraryStore、ContinuousReaderPages | ReaderSessionTests、ReaderLoadStateTests、LibraryStoreTests、ContinuousReaderPagesTests、ReaderMangaGeometryTests、ReaderSettingsParityUITests、ReaderContinuityUITests | 待验收；实际结果另核对 |
| READER-09 | ReaderSettingsViewController、ReaderViewController、RemoteImageView、ReaderPreferences、WhiteMarginDetector、ImageEnhancementPolicy | PreferencesTests、WhiteMarginTests、ImageEnhancementPolicyTests、ReaderSettingsParityUITests、VisualMatrixUITests | 待验收；实际结果另核对 |
| READER-10 | ReaderEnhancementEngine、RemoteImageView、ReaderSettingsViewController、ImageEnhancementPolicy | ImageEnhancementPolicyTests、ReaderEnhancementEngineTests、ReaderEnhancementUITests | 待验收；实际结果另核对 |
| READER-11 | ReaderEnhancementEngine、RemoteImageView、ImageEnhancementPolicy | ImageEnhancementPolicyTests、ReaderEnhancementEngineTests、ReaderEnhancementUITests | 待验收；实际结果另核对 |
| READER-12 | RemoteImageView、ReaderViewController、ReaderPageLayout、LocalImageProbe、ReaderLoadState | LocalImageProbeTests、ReaderLoadStateTests、ReaderEnhancementEngineTests、OfflineDownloadImageTests、ReaderContinuityUITests、CurrentParityUITests | 待验收；实际结果另核对 |
| READER-13 | ComicGridViewController、DetailViewController、LocalReadingTarget、EpubComicContent | LocalReadingRoutingTests、LegacyTextRecordTests、EpubComicContentTests、EpubReadingUITests | 用户移除；实际结果另核对 |
| READER-14 | ReaderViewController、ContinuousReaderPages、ReaderSession | ContinuousReaderPagesTests、ReaderSessionTests、ReaderContinuityUITests | 待验收；实际结果另核对 |
| LOCAL-01 | ComicGridViewController、ReaderViewController、LocalArchiveIndex、LocalLibrary | LocalArchiveTests、LocalLibraryTests、LocalImportPreparationTests、BatchImportRecoveryUITests、VolumeManagerParityUITests | 待验收；实际结果另核对 |
| LOCAL-02 | ComicGridViewController、DetailViewController、ReaderViewController、LocalEpubLibrary、EpubComicContent、LocalReadingTarget | LocalEpubLibraryTests、EpubComicContentTests、EpubParserTests、LocalReadingRoutingTests、LegacyTextRecordTests、EpubReadingUITests | 待验收；实际结果另核对 |
| LOCAL-03 | ComicGridViewController、ReaderViewController、LocalPdfLibrary、PdfRenderer、LocalKindleLibrary、KindlePublicationAdapter | LocalPdfLibraryTests、PdfRendererTests、LocalKindleLibraryTests、KindlePublicationTests、KindleFormatTests、EpubReadingUITests、VolumeManagerParityUITests | 待验收；实际结果另核对 |
| LOCAL-04 | BatchImportConfirmationViewController、ComicGridViewController、BatchImportPlanner、BatchImportSession、BatchImportWorker | BatchImportPlannerTests、BatchImportSessionTests、BatchImportWorkerTests、BatchImportRecoveryUITests | 待验收；实际结果另核对 |
| LOCAL-05 | VolumeManagerViewController、DetailViewController、LocalLibrary、LocalCatalog | LocalSeriesLifecycleTests、LocalLibraryTests、LocalCatalogTests、VolumeManagerParityUITests、BatchImportRecoveryUITests | 待验收；实际结果另核对 |
| LOCAL-06 | ComicGridViewController、ContentFingerprint、LocalCatalog、LocalLibrary | ContentFingerprintTests、LocalCatalogTests、LocalImportFingerprintTests、LocalLibraryTests、LocalDeletionParityUITests、BatchImportRecoveryUITests | 待验收；实际结果另核对 |
| LOCAL-07 | ComicGridViewController、LocalStorageViewController、FolderBookmarkStore、LinkedFolderLibrary | FolderBookmarkStoreTests、LinkedFolderLibraryTests、LocalFolderTests、ExternalFilesParityUITests、LinkedFolderParityUITests | 待验收；实际结果另核对 |
| LOCAL-08 | AppEnvironment、LocalStorageViewController、SceneDelegate、LocalFolderSync、LinkedFolderLibrary | LocalFolderSyncTests、LinkedFolderLibraryTests、ExternalFilesParityUITests、LinkedFolderParityUITests | 待验收；实际结果另核对 |
| LOCAL-09 | ComicGridViewController、LocalDeletionController、LocalLibrary、LocalImportJournal、FileAccessCoordinator、LocalCatalog | LocalOwnershipRecoveryTests、LocalLibraryTests、LocalImportPreparationTests、LocalCatalogTests、LocalDeletionParityUITests、VolumeManagerParityUITests | 待验收；实际结果另核对 |
| LOCAL-10 | LocalDeletionController、ComicGridViewController、DeferredDeletionQueue、DownloadRuntime、LocalLibrary | DeferredDeletionTests、DownloadDeletionTests、DownloadFileCoordinationTests、LocalSeriesLifecycleTests、LocalDeletionParityUITests、CurrentParityUITests | 待验收；实际结果另核对 |
| DOWNLOAD-01 | DownloadSelectionViewController、DownloadCenterViewController、DetailViewController、ComicGridViewController、DownloadRuntime、DownloadStore、DownloadCoordinator | DownloadRuntimeTests、DownloadStoreTests、DownloadCoordinatorTests、CurrentParityUITests、DownloadLifecycleUITests | 待验收；实际结果另核对 |
| DOWNLOAD-02 | DownloadCenterViewController、DownloadLifecycleController、DownloadRuntime、FileDownloadWorker、DownloadStore | DownloadRuntimeTests、FileDownloadWorkerTests、DownloadPersistenceTests、DownloadSchedulingTests、DownloadLifecycleTests、DownloadLifecycleUITests、CurrentParityUITests | 待验收；实际结果另核对 |
| DOWNLOAD-03 | ReaderViewController、ComicGridViewController、DownloadCenterViewController、RemoteImageView、DownloadRuntime、DownloadOwnedDirectory | DownloadRuntimeTests、DownloadDeletionTests、DownloadOwnedDirectoryTests、OfflineDownloadImageTests、CurrentParityUITests、DownloadLifecycleUITests、ExternalFilesParityUITests | 待验收；实际结果另核对 |
| DOWNLOAD-04 | DownloadLocationViewController、AppEnvironment、DownloadStorageLocations、DownloadOwnedDirectory | DownloadLocationTests、DownloadOwnedDirectoryTests、DownloadIdentityTests、ExternalFilesParityUITests、DownloadLocationParityUITests | 待验收；实际结果另核对 |
| DOWNLOAD-05 | DownloadLifecycleController、AppEnvironment、SceneDelegate、SettingsViewController、DownloadRuntime、NetworkMonitor | DownloadSchedulingTests、DownloadRuntimeTests、DownloadLifecycleTests、DownloadLifecycleUITests | 待验收；实际结果另核对 |
| DOWNLOAD-06 | DownloadCenterViewController、DownloadCoordinator、FileDownloadWorker | FileDownloadWorkerTests | 通过；实际结果另核对 |
| DOWNLOAD-07 | DownloadCenterViewController、DownloadStore、DownloadRuntime | DownloadPersistenceTests、DownloadRuntimeTests、DownloadStoreTests、CurrentParityUITests、DownloadLifecycleUITests | 待验收；实际结果另核对 |
| VERIFY-01 | SourceVerificationUI、Mh18BrowserSession、SourceSettingsViewController、Mh18VerificationRules、Mh18VerificationAttempt、Mh18CookieSynchronizer、Mh18BrowserTrust | Mh18VerificationRulesTests、Mh18VerificationAttemptTests、Mh18CookieSynchronizerTests、Mh18BrowserTrustTests、Mh18VerificationTests | 待验收；实际结果另核对 |
| GATE-01 | build、release_product、NON_SOURCE_GATE | 综合门槛/范围核对 | 待核对；实际结果另核对 |
| GATE-02 | build、release_product、NON_SOURCE_GATE | 综合门槛/范围核对 | 待验收；实际结果另核对 |
| GATE-03 | build、release_product、NON_SOURCE_GATE | 综合门槛/范围核对 | 待验收；实际结果另核对 |
| GATE-04 | build、release_product、NON_SOURCE_GATE | 综合门槛/范围核对 | 待验收；实际结果另核对 |
| GATE-05 | build、release_product、NON_SOURCE_GATE | 综合门槛/范围核对 | 待验收；实际结果另核对 |
| GATE-06 | build、release_product、NON_SOURCE_GATE | 综合门槛/范围核对 | 待验收；实际结果另核对 |
| SOURCE-01 | SourceSettingsViewController、AppEnvironment、AboutAppViewController、BuiltinSourceCatalog、SourcePreferences、RetiredComicSource | BuiltinSourceCatalogTests、RetiredComicSourceTests、SourcePreferencesTests、BuiltinSourceRegistrationTests、SourceConfigFilesUITests、SettingsParityUITests | 待验收；实际结果另核对 |
| SOURCE-02 | 用户后置 | 综合门槛/范围核对 | 后置站源；实际结果另核对 |
| SOURCE-03 | 用户后置 | 综合门槛/范围核对 | 后置站源；实际结果另核对 |
| SOURCE-04 | 用户后置 | 综合门槛/范围核对 | 后置站源；实际结果另核对 |
| FINAL-01 | build、release_product、NON_SOURCE_GATE | 综合门槛/范围核对 | 待验收；实际结果另核对 |
| FINAL-02 | build、release_product、NON_SOURCE_GATE | 综合门槛/范围核对 | 待验收；实际结果另核对 |

[逐引用哈希、冻结路径与具体测试方法](consumer-map.json)。Core、原生、UI、视觉分别核对；测试总数或文件存在不能代全部状态。
