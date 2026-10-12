#!/usr/bin/env python3
"""Build a static trace from stable requirement IDs to existing consumers/tests.

This is an inventory, never runtime evidence or an automatic PASS decision.
Android references resolve only against the frozen Git object, not app/ here.
"""
import csv
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
BASELINE = "696e80a44ab36b19de6f630565df32978e55a19e"
# ID | app consumers | Core consumers | Core tests | native tests | UI tests
MAPPING = """
VIS-01|AppThemeController Palette ThemeChoiceSheet|AppTheme|AppTheme Preferences||SettingsParityUITests VisualMatrixUITests
VIS-02|ParityIcon RemoteImageView|BuiltinSourceCatalog|BuiltinSourceCatalog|CoverFallbackTests|AppNavigationTests VisualMatrixUITests
VIS-03|RootTabsViewController ReaderChromeViews|AppTheme|AppTheme|RootTabGeometryTests|RootNavigationParityUITests ReaderToolbarParityUITests VisualMatrixUITests
VIS-04|ComicGridViewController DiscoverViewController DetailViewController RemoteImageView|BookshelfLayoutHelper BookshelfReadingStatus|BookshelfReadingStatus|CoverFallbackTests|BookshelfParityUITests VisualMatrixUITests
VIS-05|ChapterDrawerSheet ReaderSettingsViewController SourceOptionScrollView FilterDrawerNavigationController ThemeChoiceSheet||SourceFilterSelection||SourceDrawerTests ReaderSettingsParityUITests VisualMatrixUITests
VIS-06|DetailFeedbackState DetailViewController RemoteImageView SourceVerificationUI|ReaderLoadState ComicDirectoryPreparation|ReaderLoadState ComicDirectoryPreparation|CoverFallbackTests DetailFeedbackStateTests|CurrentParityUITests Mh18VerificationTests
VIS-07|RootTabsViewController ThemeChoiceSheet VolumeManagerViewController ChapterDrawerSheet|AppTheme|AppTheme|RootTabGeometryTests|VisualMatrixUITests RootNavigationParityUITests VolumeManagerParityUITests
SHELF-01|ComicGridViewController BookshelfTabsView|BookshelfLayoutHelper|Preferences||BookshelfParityUITests VisualMatrixUITests
SHELF-02|BookshelfGroupSheet BookshelfGroupSelectSheet ComicGridViewController|BookshelfGroupStore|BookshelfGroupStore||BookshelfParityUITests
SHELF-03|ComicGridViewController|LibraryStore|LibraryStore||BookshelfParityUITests
SHELF-04|ComicGridViewController BookshelfResumeView|FavoriteUpdateChecker FavoriteUpdateCoordinator BookshelfReadingStatus LibraryStore|FavoriteUpdateChecker FavoriteRevision BookshelfReadingStatus LibraryStore||BookshelfParityUITests SettingsParityUITests
SHELF-05|SourceSwitchSheet AppEnvironment ComicGridViewController|LibraryStore ChapterMatching|LibraryStore ChapterMatching|SourceReplacementTransactionTests|SourceSwitchParityUITests
SHELF-06|FloatingImportBubble ComicGridViewController|BatchImportSession LocalImportPreparation|BatchImportSession LocalImportPreparation||BatchImportRecoveryUITests EpubReadingUITests ExternalFilesParityUITests
HISTORY-01|ComicGridViewController SettingsViewController DiscoverViewController|LibraryStore|LibraryStore||SettingsParityUITests BookshelfParityUITests
DISC-01|DiscoverViewController SourceGroupSheet AppEnvironment|SourceGroupStore SourcePreferences|SourceGroupStore SourcePreferences||SourceDrawerTests SourceGroupsParityUITests CurrentParityUITests
DISC-02|DiscoverViewController|SearchRules|SearchRules SourceSearchTrim||CurrentParityUITests VisualMatrixUITests
DISC-03|DiscoverViewController|SearchRules|SearchRules||SourceDrawerTests CurrentParityUITests
DISC-04|DiscoverViewController SourceOptionScrollView FilterDrawerNavigationController|SourceFilterSelection DiscoveryHeaderGesture|SourceFilterSelection DiscoveryHeaderGesture||SourceDrawerTests CurrentParityUITests VisualMatrixUITests
DETAIL-01|DetailViewController DetailFeedbackState RemoteImageView|ComicDirectoryPreparation LibraryStore|ComicDirectoryPreparation LibraryStore|DetailFeedbackStateTests CoverFallbackTests|CurrentParityUITests VisualMatrixUITests
DETAIL-02|SourceSwitchSheet DetailViewController AppEnvironment|SearchRules ChapterMatching ComicDirectoryPreparation|SearchRules ChapterMatching ComicDirectoryPreparation|SourceReplacementTransactionTests|SourceSwitchParityUITests
CONFIG-01|SettingsViewController ThemeChoiceSheet ReaderSettingsViewController|ReaderPreferences AppTheme|Preferences AppTheme ImageEnhancementPolicy||SettingsParityUITests ReaderSettingsParityUITests AppNavigationTests
CONFIG-02|AppEnvironment SourceSettingsViewController SourceGroupSheet|SourcePreferences SourceConfigDocuments PublicSourceRegistry|SourcePreferences SourceImportContract SourceConfigDocuments RetiredComicSource|BuiltinSourceRegistrationTests|SourceConfigFilesUITests SourceGroupsParityUITests SourceDrawerTests
CONFIG-03|SourceSettingsViewController|SourceConfigDocuments SourcePreferences|SourceConfigDocuments SourceImportContract SourcePreferences||SourceConfigFilesUITests
CONFIG-04|CacheCleanupViewController SettingsViewController RemoteImageView Mh18BrowserSession|HTTPResponseCache StorageCalculator|CacheMaintenance CacheLateRestore CacheBackendContinuity StorageCalculator|CacheMaintenanceNativeTests WebCacheCleanupTests|SettingsParityUITests VisualMatrixUITests
CONFIG-05|ErrorLogsViewController SettingsViewController|ErrorLogStore ErrorLogSanitizer|ErrorLogStore||ErrorLogsParityUITests
CONFIG-06|AboutAppViewController SettingsViewController|AppUpdateChecker IOSUpdatePolicy|AppUpdateChecker IOSUpdatePolicy||SettingsParityUITests
CONFIG-07|SettingsViewController SceneDelegate AppEnvironment|UsageStatsClient|UsageStatsClient UsageStatsReporting||SettingsParityUITests
READER-01|ReaderViewController ReaderPageLayout ReaderSettingsViewController|ReaderPreferences ReadingRules|Preferences ReadingRules|ReaderMangaGeometryTests|ReaderSettingsParityUITests ReaderContinuityUITests
READER-02|ReaderViewController ReaderPageLayout|ReadingRules|ReadingRules|ReaderMangaGeometryTests|ReaderSettingsParityUITests ReaderContinuityUITests
READER-03|ReaderChromeViews ReaderViewController|ReaderSession|ReaderSession||ReaderToolbarParityUITests ReaderContinuityUITests VisualMatrixUITests
READER-04|ReaderSeekBar ReaderViewController|ReaderSeekSession|ReaderSeekSession|ReaderSeekGeometryTests|ReaderContinuityUITests ReaderToolbarParityUITests
READER-05|ChapterDrawerSheet ChapterFastScroller ReaderViewController|ComicDirectoryPreparation ChapterMatching|ComicDirectoryPreparation ChapterMatching||ReaderContinuityUITests VisualMatrixUITests
READER-06|ChapterDrawerSheet ChapterFastScroller ReaderViewController||ChapterMatching||ReaderContinuityUITests
READER-07|SourceSwitchSheet ReaderViewController DetailViewController AppEnvironment|LibraryStore ChapterMatching|LibraryStore ChapterMatching|SourceReplacementTransactionTests|SourceSwitchParityUITests
READER-08|ReaderViewController ReaderPageLayout SceneDelegate|ReaderSession ReaderLoadState LibraryStore ContinuousReaderPages|ReaderSession ReaderLoadState LibraryStore ContinuousReaderPages|ReaderMangaGeometryTests|ReaderSettingsParityUITests ReaderContinuityUITests
READER-09|ReaderSettingsViewController ReaderViewController RemoteImageView|ReaderPreferences WhiteMarginDetector ImageEnhancementPolicy|Preferences WhiteMargin ImageEnhancementPolicy||ReaderSettingsParityUITests VisualMatrixUITests
READER-10|ReaderEnhancementEngine RemoteImageView ReaderSettingsViewController|ImageEnhancementPolicy|ImageEnhancementPolicy|ReaderEnhancementEngineTests|ReaderEnhancementUITests
READER-11|ReaderEnhancementEngine RemoteImageView|ImageEnhancementPolicy|ImageEnhancementPolicy|ReaderEnhancementEngineTests|ReaderEnhancementUITests
READER-12|RemoteImageView ReaderViewController ReaderPageLayout|LocalImageProbe ReaderLoadState|LocalImageProbe ReaderLoadState|ReaderEnhancementEngineTests OfflineDownloadImageTests|ReaderContinuityUITests CurrentParityUITests
READER-13|ComicGridViewController DetailViewController|LocalReadingTarget EpubComicContent|LocalReadingRouting LegacyTextRecord EpubComicContent||EpubReadingUITests
READER-14|ReaderViewController|ContinuousReaderPages ReaderSession|ContinuousReaderPages ReaderSession||ReaderContinuityUITests
LOCAL-01|ComicGridViewController ReaderViewController|LocalArchiveIndex LocalLibrary|LocalArchive LocalLibrary LocalImportPreparation||BatchImportRecoveryUITests VolumeManagerParityUITests
LOCAL-02|ComicGridViewController DetailViewController ReaderViewController|LocalEpubLibrary EpubComicContent LocalReadingTarget|LocalEpubLibrary EpubComicContent EpubParser LocalReadingRouting LegacyTextRecord||EpubReadingUITests
LOCAL-03|ComicGridViewController ReaderViewController|LocalPdfLibrary PdfRenderer LocalKindleLibrary KindlePublicationAdapter|LocalPdfLibrary PdfRenderer LocalKindleLibrary KindlePublication KindleFormat||EpubReadingUITests VolumeManagerParityUITests
LOCAL-04|BatchImportConfirmationViewController ComicGridViewController|BatchImportPlanner BatchImportSession BatchImportWorker|BatchImportPlanner BatchImportSession BatchImportWorker||BatchImportRecoveryUITests
LOCAL-05|VolumeManagerViewController DetailViewController|LocalLibrary LocalCatalog|LocalSeriesLifecycle LocalLibrary LocalCatalog||VolumeManagerParityUITests BatchImportRecoveryUITests
LOCAL-06|ComicGridViewController|ContentFingerprint LocalCatalog LocalLibrary|ContentFingerprint LocalCatalog LocalImportFingerprint LocalLibrary||LocalDeletionParityUITests BatchImportRecoveryUITests
LOCAL-07|ComicGridViewController LocalStorageViewController|FolderBookmarkStore LinkedFolderLibrary|FolderBookmarkStore LinkedFolderLibrary LocalFolder||ExternalFilesParityUITests LinkedFolderParityUITests
LOCAL-08|AppEnvironment LocalStorageViewController SceneDelegate|LocalFolderSync LinkedFolderLibrary|LocalFolderSync LinkedFolderLibrary||ExternalFilesParityUITests LinkedFolderParityUITests
LOCAL-09|ComicGridViewController LocalDeletionController|LocalLibrary LocalImportJournal FileAccessCoordinator LocalCatalog|LocalOwnershipRecovery LocalLibrary LocalImportPreparation LocalCatalog||LocalDeletionParityUITests VolumeManagerParityUITests
LOCAL-10|LocalDeletionController ComicGridViewController|DeferredDeletionQueue DownloadRuntime LocalLibrary|DeferredDeletion DownloadDeletion DownloadFileCoordination LocalSeriesLifecycle||LocalDeletionParityUITests CurrentParityUITests
DOWNLOAD-01|DownloadSelectionViewController DownloadCenterViewController DetailViewController ComicGridViewController|DownloadRuntime DownloadStore DownloadCoordinator|DownloadRuntime DownloadStore DownloadCoordinator||CurrentParityUITests DownloadLifecycleUITests
DOWNLOAD-02|DownloadCenterViewController DownloadLifecycleController|DownloadRuntime FileDownloadWorker DownloadStore|DownloadRuntime FileDownloadWorker DownloadPersistence DownloadScheduling|DownloadLifecycleTests|DownloadLifecycleUITests CurrentParityUITests
DOWNLOAD-03|ReaderViewController ComicGridViewController DownloadCenterViewController RemoteImageView|DownloadRuntime DownloadOwnedDirectory|DownloadRuntime DownloadDeletion DownloadOwnedDirectory|OfflineDownloadImageTests|CurrentParityUITests DownloadLifecycleUITests ExternalFilesParityUITests
DOWNLOAD-04|DownloadLocationViewController AppEnvironment|DownloadStorageLocations DownloadOwnedDirectory|DownloadLocation DownloadOwnedDirectory DownloadIdentity||ExternalFilesParityUITests DownloadLocationParityUITests
DOWNLOAD-05|DownloadLifecycleController AppEnvironment SceneDelegate SettingsViewController|DownloadRuntime NetworkMonitor|DownloadScheduling DownloadRuntime|DownloadLifecycleTests|DownloadLifecycleUITests
DOWNLOAD-06|DownloadCenterViewController|DownloadCoordinator FileDownloadWorker|FileDownloadWorker||
DOWNLOAD-07|DownloadCenterViewController|DownloadStore DownloadRuntime|DownloadPersistence DownloadRuntime DownloadStore||CurrentParityUITests DownloadLifecycleUITests
VERIFY-01|SourceVerificationUI Mh18BrowserSession SourceSettingsViewController|Mh18VerificationRules Mh18VerificationAttempt Mh18CookieSynchronizer Mh18BrowserTrust|Mh18VerificationRules Mh18VerificationAttempt Mh18CookieSynchronizer Mh18BrowserTrust||Mh18VerificationTests
SOURCE-01|SourceSettingsViewController AppEnvironment AboutAppViewController|BuiltinSourceCatalog SourcePreferences RetiredComicSource|BuiltinSourceCatalog RetiredComicSource SourcePreferences|BuiltinSourceRegistrationTests|SourceConfigFilesUITests SettingsParityUITests
"""


def fingerprint(path):
    data = (ROOT / path).read_bytes()
    return {"path": path, "sha256": hashlib.sha256(data).hexdigest()}


def files(names, directory, suffix=".swift"):
    return [fingerprint(f"{directory}/{name}{suffix}") for name in names.split()]


def main():
    requirements = list(csv.DictReader((ROOT / "docs/ios-parity-2.0.40/requirements.csv").open(encoding="utf-8-sig")))
    mapping = {parts[0]: parts[1:] for line in MAPPING.strip().splitlines() if (parts := line.split("|"))}
    frozen_paths = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", BASELINE], cwd=ROOT, text=True).splitlines()
    results = []
    for req in requirements:
        item = {"id": req["id"], "requirement": req["requirement"], "matrixStatus": req["status"], "frozenReferences": [], "consumerTrace": [], "testTrace": [], "currentRuntimeResult": None}
        for reference in req["android_reference"].split(";"):
            reference = reference.split(":")[0]
            matches = [p for p in frozen_paths if p == reference or p.endswith("/" + reference)]
            for path in matches:
                data = subprocess.check_output(["git", "show", f"{BASELINE}:{path}"], cwd=ROOT)
                item["frozenReferences"].append({"path": path, "sha256": hashlib.sha256(data).hexdigest()})
        if req["id"] in mapping:
            app, core, core_tests, native, ui = mapping[req["id"]]
            item["consumerTrace"] = files(app, "ios/XXComic") + files(core, "ios/ComicCore/Sources/ComicCore")
            item["testTrace"] = files(" ".join(name + "Tests" for name in core_tests.split()), "ios/ComicCore/Tests/ComicCoreTests") + files(native, "ios/XXComicTests") + files(ui, "ios/XXComicUITests")
            for test in item["testTrace"]:
                content = (ROOT / test["path"]).read_text(encoding="utf-8")
                test["declaredMethods"] = re.findall(r"^\s*func\s+(test\w*)\s*\(", content, re.M)
                assert test["declaredMethods"], test["path"]
            item["boundary"] = "当前消费者和检查引用已定位；源码声明不证明全部状态覆盖，必须结合最终同输入实际结果与人工审查。"
        elif req["gate"] in ("P0", "P5", "P7"):
            item["consumerTrace"] = [fingerprint(p) for p in ["ios/scripts/build.sh", "ios/scripts/release_product.py", "docs/ios-parity-2.0.40/NON_SOURCE_GATE.md"]]
            item["boundary"] = "综合门槛，须按独立构建/Core/原生/UI/视觉/资源/恢复实证核对，不由测试总数自动通过。"
        elif req["id"] in ("SOURCE-02", "SOURCE-03", "SOURCE-04"):
            item["boundary"] = "用户暂停真实站源验收；不运行、不标通过、不自动恢复。"
        else:
            raise ValueError("Unmapped stable requirement: " + req["id"])
        if req["id"] == "READER-13":
            item["boundary"] = "用户移除文字阅读/排版；保留原包/旧JSON与明确拒绝入口，相关检查只验证漫画范围及数据保护。"
        if req["id"] in ("CONFIG-02", "VERIFY-01"):
            item["boundary"] += " 仅通用配置/确定性协议或本机交互，真实站点消费和认证继续后置。"
        if req["id"] == "DOWNLOAD-06":
            item["boundary"] = "冻结当前源没有FileSourceCapability实现；只核对范围，不能用占位协议推断缺功能，也不作为队列实际运行证据。"
        results.append(item)
    output = ROOT / "docs/ios-parity-2.0.40/review-evidence/2026-10-13-requirement-consumers"
    output.mkdir(exist_ok=True)
    report = {"baseline": BASELINE, "baseRevision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(), "inputIdentity": "Actual working-file SHA256 per reference; baseRevision may precede uncommitted changes", "checkedAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(), "isRuntimeResult": False, "count": len(results), "requirements": results}
    (output / "consumer-map.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    rows = ["# 全需求入口与消费者对应表", "", "按76个稳定ID定位当前生产消费者及检查引用，记录路径、方法和SHA。冻结Android引用只从696e80a Git对象读取。这里是静态追溯表，不是运行结果，不自动改变需求状态；同版本完整Apple及人工视觉仍待核对。", "", "文字阅读/排版按用户要求移除，保留漫画导入及旧数据保护。SOURCE-02~04继续暂停；CONFIG-02与VERIFY-01仅通用配置/本机交互，不证明真实网站消费或认证通过。", "", "| ID | 生产入口/消费者 | 对应检查 | 当前边界 |", "| --- | --- | --- | --- |"]
    for item in results:
        consumers = "、".join(Path(p["path"]).stem for p in item["consumerTrace"])
        tests = "、".join(Path(p["path"]).stem for p in item["testTrace"])
        rows.append("| " + item["id"] + " | " + (consumers or "用户后置") + " | " + (tests or "综合门槛/范围核对") + " | " + item["matrixStatus"] + "；实际结果另核对 |")
    rows += ["", "[逐引用哈希、冻结路径与具体测试方法](consumer-map.json)。Core、原生、UI、视觉分别核对；测试总数或文件存在不能代全部状态。"]
    (output / "README.md").write_text("\n".join(rows) + "\n", encoding="utf-8")
    print(json.dumps({"requirements": len(results), "consumerFiles": len({p["path"] for r in results for p in r["consumerTrace"]}), "testFiles": len({p["path"] for r in results for p in r["testTrace"]}), "runtimeEvidence": False}))


if __name__ == "__main__":
    main()
