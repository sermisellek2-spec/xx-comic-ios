import os, pathlib, subprocess, tempfile
assert pathlib.Path('/.dockerenv').exists(), 'Run only in the documented disposable Linux container'
source=pathlib.Path('/work/ios/scripts/build.sh').read_text()
plist=pathlib.Path('/usr/libexec/PlistBuddy'); plist.parent.mkdir(parents=True,exist_ok=True)
assert not plist.exists(), 'Never replace a real compiler utility'
plist.write_text('#!/bin/sh\nprintf "340\\n"\n'); plist.chmod(0o755)
for scenario, expected in [('core-failure',1),('sdk-failure',23)]:
    with tempfile.TemporaryDirectory(prefix='xxcomic-driver-') as tmp:
        root=pathlib.Path(tmp); scripts=root/'ios/scripts'; scripts.mkdir(parents=True)
        driver=scripts/'build.sh'; driver.write_text(source)
        (scripts/'export_evidence.py').write_text('print("SYNTHETIC_EXPORT")\n')
        binpath=root/'bin'; binpath.mkdir()
        commands={
          'xcodegen':'#!/bin/sh\nexit 0\n',
          'swift':'#!/bin/sh\necho swift >> "$CONTRACT_LOG"\n[ "$CONTRACT_SCENARIO" != core-failure ]\n',
          'xcrun':'#!/bin/sh\nexit 0\n',
          'xcodebuild':'#!/bin/sh\nprintf \'%s\n\' "$*" >> "$CONTRACT_LOG"\nif [ "$CONTRACT_SCENARIO" = sdk-failure ]; then exit 23; fi\nexit 0\n'}
        for name, body in commands.items():
            f=binpath/name; f.write_text(body); f.chmod(0o755)
        log=root/'calls.log'
        env=dict(os.environ,PATH=str(binpath)+':'+os.environ['PATH'],CONTRACT_LOG=str(log),CONTRACT_SCENARIO=scenario,IOS_TEST_DESTINATION='platform=iOS Simulator,id=phone-fixture',IOS_IPAD_DESTINATION='platform=iOS Simulator,id=tablet-fixture',IOS_VALIDATION_SCOPE='full',IOS_PACKAGE_IPA='true')
        result=subprocess.run(['bash',str(driver)],env=env,text=True,capture_output=True)
        calls=log.read_text().splitlines()
        ui=[c for c in calls if c.endswith(' test')]
        assert result.returncode==expected,(scenario,result.returncode,result.stderr)
        assert len(ui)==(2 if scenario=='core-failure' else 0),(scenario,ui)
        assert not (root/'ios/build/XXComic-unsigned.ipa').exists()
        if scenario=='core-failure':
            assert 'Native tests failed; Release IPA will not be packaged.' in result.stderr
            assert 'phone-fixture' in ui[0] and 'tablet-fixture' in ui[1]
        else: assert 'swift' not in calls
        print('SYNTHETIC_DRIVER_CONTRACT',scenario,'exit='+str(result.returncode),'independentUI='+str(len(ui)),'IPA=false')
