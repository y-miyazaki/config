# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

[Full diff](https://github.com/y-miyazaki/config/compare/a8506d6d80b7a549a0e3c275448a33c7523cf343...aedf254a07200a1d8f2149e9eb7f6c794dec578f)

### Changed

- Append run log [skip ci] (loop) ([ee4621c](https://github.com/y-miyazaki/config/commit/ee4621c2ac098926e527ee906961c696e74cea4d))
- Update state [skip ci] (loop) ([0422afb](https://github.com/y-miyazaki/config/commit/0422afbbf1b3bd50145053dac06268c49ea03fd1))
- Update minimumReleaseAge in renovate configuration to 7 days ([86bb02f](https://github.com/y-miyazaki/config/commit/86bb02f9a5d34ffc8f298a944e7d8ff9a951951b))
- Update workflow references to local paths and add package rules in renovate configuration ([2e4f7b1](https://github.com/y-miyazaki/config/commit/2e4f7b1e79217aa13facf32ae1fc6979de6dce29))

#### Dependencies

- Update dependency @upstash/context7-mcp to v3.2.4 (#490) (apm-mcp) ([b91471e](https://github.com/y-miyazaki/config/commit/b91471e00eec73d37f5dc5c3806de18bafaccfa0))

## [1.8.58] - 2026-07-24

### Changed

- Align pins to v1.8.58 (00d6e7a) ([13b8716](https://github.com/y-miyazaki/config/commit/13b8716bc3eb1d11619c8022f80cba8f38c3bf75))
- Finalize all pins v1.8.58 (c818d6c) ([00d6e7a](https://github.com/y-miyazaki/config/commit/00d6e7a9346341b5fc6318893ff71b80b670fd62))
- Pin all to release v1.8.58 (b1c4110) ([c818d6c](https://github.com/y-miyazaki/config/commit/c818d6c404ca672512bd1d7231974dac1fe75454))
- Pin all to v1.8.58 (106926f) ([b1c4110](https://github.com/y-miyazaki/config/commit/b1c4110f992be284bb6a1e207e06f59f67cfe78b))
- Align pins to v1.8.58 (1886b9d) ([106926f](https://github.com/y-miyazaki/config/commit/106926ff4d4e84109c6dcdb16a61ecbd966ecd61))
- Finalize all pins v1.8.58 (64908f2) ([1886b9d](https://github.com/y-miyazaki/config/commit/1886b9d92c1a1d034504e603077fc297e339ef99))
- Pin all to release v1.8.58 (ec816cc) ([64908f2](https://github.com/y-miyazaki/config/commit/64908f2134838ff412f5802863a86f5f7aac7107))
- Pin all to v1.8.58 (77f2b97) ([ec816cc](https://github.com/y-miyazaki/config/commit/ec816cc734f6e25bfe7a1d3339a9b8d181448339))

#### Dependencies

- Update github/codeql-action action to v4.37.1 (#487) (github-actions) ([77f2b97](https://github.com/y-miyazaki/config/commit/77f2b9727e7593499da829e05512547f8966150a))
- Update dependency pipx:headroom-ai to v0.32.0 (#488) (mise) ([eb701c5](https://github.com/y-miyazaki/config/commit/eb701c55e79594321956572cea9fa80474f18520))
- Update dependency aqua:aws/aws-cli to v2.36.1 (#483) (mise) ([a18b614](https://github.com/y-miyazaki/config/commit/a18b614f4aed57d1201445a4c2444c731c54dfcb))

## [1.8.57] - 2026-07-24

### Changed

- Update workflow references to use pinned version v1.8.57 (71c3497) ([62b2021](https://github.com/y-miyazaki/config/commit/62b2021d83b24d5cbb8b241780a2a4a01d56b306))
- Align pins to v1.8.57 (71c3497) ([c690bc8](https://github.com/y-miyazaki/config/commit/c690bc874e1897d700f0d2ca238689c4d5a1bf56))
- Finalize all pins v1.8.57 (4c8d7b7) ([71c3497](https://github.com/y-miyazaki/config/commit/71c34979da6e9fc36c18431859f68c2680a5bb9f))
- Pin all to release v1.8.57 (ad2e210) ([4c8d7b7](https://github.com/y-miyazaki/config/commit/4c8d7b77ac04e78de8fac8e29e9015e65c2825a8))
- Pin all to v1.8.57 (472eb2f) ([ad2e210](https://github.com/y-miyazaki/config/commit/ad2e210367ae06aa3aac7cc3ef7d2642f89d38e6))
- Add dependency review detection to CI workflow (ci) ([472eb2f](https://github.com/y-miyazaki/config/commit/472eb2f050d25a4f2498ac83d8043fc58c073ab1))
- Enhance Semgrep integration and update configurations ([8722cd1](https://github.com/y-miyazaki/config/commit/8722cd11d5e9fae16608fcf37a2846e8ccd80868))
- Enhance Semgrep integration in CI workflow (ci) ([35ffa0d](https://github.com/y-miyazaki/config/commit/35ffa0da44bb3a206926a2664379cae859720c28))
- Update Semgrep version and add Python version input (ci) ([3fbe09b](https://github.com/y-miyazaki/config/commit/3fbe09ba7cdc3392026e5fdae336e3903205e863))
- Update Trivy version pinning in workflows ([5b108da](https://github.com/y-miyazaki/config/commit/5b108da8bb705932607af92ca1e4c6f26fbe7888))

## [1.8.56] - 2026-07-24

### Added

- Introduce reusable security workflows for SAST and repository security (ci) ([07adb7b](https://github.com/y-miyazaki/config/commit/07adb7ba6fa34179e5bff2e68a10d52185c5ca8a))
- Add reusable Node.js CI workflows (#484) (ci) ([a11b88c](https://github.com/y-miyazaki/config/commit/a11b88c4cbe2d9777af0ae16ecda35677f64bbcf))

### Changed

- Align pins to v1.8.56 (01a42fc) ([6b9399b](https://github.com/y-miyazaki/config/commit/6b9399b9760a9d503b53a425c2578325cf669bb7))
- Finalize all pins v1.8.56 (f14ec53) ([01a42fc](https://github.com/y-miyazaki/config/commit/01a42fc43c278cf8a38616de8de24fe7b6285f04))
- Pin all to release v1.8.56 (d762c84) ([f14ec53](https://github.com/y-miyazaki/config/commit/f14ec53d76fb53f7ab680efbb57f19a57984ec3d))
- Pin all to v1.8.56 (5878bad) ([d762c84](https://github.com/y-miyazaki/config/commit/d762c84d08efb85873bd4847a76f281b74225315))
- Update Python setup action to v6.3.0 in CI workflow (ci) ([5878bad](https://github.com/y-miyazaki/config/commit/5878bada52fcc598d0a5001753cee72294197c54))

#### Dependencies

- Update actions/setup-python digest to a309ff8 (#485) (github-actions) ([982066b](https://github.com/y-miyazaki/config/commit/982066b8edcdae7c0bcb891efd90c85c04e7636b))
- Update jdx/mise-action action to v4.2.1 (#479) (github-actions) ([fdb1b4a](https://github.com/y-miyazaki/config/commit/fdb1b4ada89dbee72b4732866183d96ad53753a0))
- Update dependency npm:markdownlint-cli2 to v0.23.1 (#482) (mise) ([58b87fc](https://github.com/y-miyazaki/config/commit/58b87fc932598f3d0c7ee6704abe436a3a6eaf91))
- Update dependency claude to v2.1.212 (#481) (mise) ([78a992e](https://github.com/y-miyazaki/config/commit/78a992e0a907db791fb34e2fc7863ae62059355b))
- Update dependency github:microsoft/waza to v0.38.2 (#480) (mise) ([070f5af](https://github.com/y-miyazaki/config/commit/070f5afd311568d453ea71229cbd005beaea1fe4))
- Update actions/setup-java action to v5.6.0 (#477) (github-actions) ([36b2101](https://github.com/y-miyazaki/config/commit/36b210107d3e03cf6a3bc3606636bb4c04796c82))
- Update dependency aqua to v2.62.0 (#478) (mise) ([88a3d03](https://github.com/y-miyazaki/config/commit/88a3d036251aeb36732213b9ce9b0245d07abe1d))

## [1.8.55] - 2026-07-23

### Changed

- Update workflow references to use pinned version v1.8.55 (5a725c4) ([88a0d96](https://github.com/y-miyazaki/config/commit/88a0d960953b8d496194cabb5f46ea0e0ce32aa1))
- Align pins to v1.8.55 (5a725c4) ([fb703bf](https://github.com/y-miyazaki/config/commit/fb703bfd2c4162503fd89ed500d98366a4374d55))
- Finalize all pins v1.8.55 (0b4f89e) ([5a725c4](https://github.com/y-miyazaki/config/commit/5a725c44406bb5a7d7e32cdc69ddf3fe20d4afd3))
- Pin all to release v1.8.55 (8591778) ([0b4f89e](https://github.com/y-miyazaki/config/commit/0b4f89e1f968713bca71b03d4b075a426bd0f326))
- Pin all to v1.8.55 (743dade) ([8591778](https://github.com/y-miyazaki/config/commit/85917784ada5a553053d0c51561705bc5d766a58))
- Add AWS service control validation action and supporting scripts ([743dade](https://github.com/y-miyazaki/config/commit/743dade98d4730c478f7a1e9711d77afd3dd185f))

## [1.8.54] - 2026-07-23

### Changed

- Align pins to v1.8.54 (59dd8fa) ([03b6b03](https://github.com/y-miyazaki/config/commit/03b6b039391eee6384df67c7b37ca5ac82dfefa6))
- Finalize all pins v1.8.54 (4329421) ([59dd8fa](https://github.com/y-miyazaki/config/commit/59dd8fabd9d9396711cb913ccc707da47634d164))
- Pin all to release v1.8.54 (cff949f) ([4329421](https://github.com/y-miyazaki/config/commit/43294212b7637ba43f3e950db9c76945e8421d0f))
- Pin all to v1.8.54 (632dbca) ([cff949f](https://github.com/y-miyazaki/config/commit/cff949f38d5776f64c289436e4daf9ec62205068))
- Sync loop skill consolidation docs (#476) (docs-triage) ([b6ae746](https://github.com/y-miyazaki/config/commit/b6ae7466e229e6f38eacffb5f1f36cba36be5a8e))
- Enhance agent report validation and synthesis (loop) ([ded9051](https://github.com/y-miyazaki/config/commit/ded9051cb49e11ffc661b10ef1e7d4fbd41c3d1b))
- Append run log [skip ci] (loop) ([969be1b](https://github.com/y-miyazaki/config/commit/969be1b04499e31df22bc4a927ee3cab3f3762d7))
- Update state [skip ci] (loop) ([7dda864](https://github.com/y-miyazaki/config/commit/7dda864426ca6a3b3279c19252bfc6aea62fb38b))
- Clear_pending state for PR #475 [skip ci] (loop) ([f3b5e84](https://github.com/y-miyazaki/config/commit/f3b5e84920c5bab2d64376d4e67af67d7c94abc4))
- Update docs-updater rename detection for improved triage reporting ([6c64b91](https://github.com/y-miyazaki/config/commit/6c64b91ec39eab6b05f63e8cc75e27f87f03b0de))

#### Dependencies

- Update dependency pnpm to v11.13.1 (#473) (mise) ([632dbca](https://github.com/y-miyazaki/config/commit/632dbca9f83fab9ab543f68f0fd0fe372a2a526a))
- Update actions/setup-go action to v7 (#474) (github-actions) ([cd0c4bf](https://github.com/y-miyazaki/config/commit/cd0c4bf6a2c3bdcb0565efab536f6815b2639f3b))

## [1.8.53] - 2026-07-23

### Added

- Add script to pin y-miyazaki/config actions workflows to specific SHAs ([c7e8c73](https://github.com/y-miyazaki/config/commit/c7e8c738ea3c50644c10ce085e31d0e313ce961d))

### Changed

- Align pins to v1.8.53 (a593e0f) ([acdf10f](https://github.com/y-miyazaki/config/commit/acdf10f11113f66f719945c2cd69c6664a0f89a6))
- Finalize all pins v1.8.53 (466ca5d) ([a593e0f](https://github.com/y-miyazaki/config/commit/a593e0f8e283e5595f1d31675a3a117bca713706))
- Pin all to release v1.8.53 (2bfcc63) ([466ca5d](https://github.com/y-miyazaki/config/commit/466ca5d7f913c7f1f69646b1645ef02ed367369c))
- Pin all to v1.8.53 (f2981bb) ([2bfcc63](https://github.com/y-miyazaki/config/commit/2bfcc63075ce3359b848a64a2c7bd5c197d4b86a))
- Enhance automation constraints and output specifications across skills ([f2981bb](https://github.com/y-miyazaki/config/commit/f2981bb87562e87ec86dd35c73c52715c67f79ec))
- Append run log [skip ci] (loop) ([d74c745](https://github.com/y-miyazaki/config/commit/d74c745a1ce02c4efe9443a398ccfe054c01367c))
- Update state [skip ci] (loop) ([fad327c](https://github.com/y-miyazaki/config/commit/fad327c43e6778fef905c100c38b3a5e582dc88a))
- Update changelog evaluation tasks and templates for improved automation and interactivity ([36472c1](https://github.com/y-miyazaki/config/commit/36472c159485f396ebbb9205e5eb35de1c5edb3a))

## [1.8.52] - 2026-07-23

### Fixed

- Update file permissions for multiple scripts to enhance security ([3fa4630](https://github.com/y-miyazaki/config/commit/3fa463043f57aebf88f82455b8b7a5bbbcbf84d7))
- Update file permissions for various scripts and adjust file mappings in install scripts ([0f13723](https://github.com/y-miyazaki/config/commit/0f13723fced57e708f54d0198bc841bfbddf5d5c))
- Update file permissions for various scripts to ensure proper execution ([b707e1f](https://github.com/y-miyazaki/config/commit/b707e1fc6c1bba7cb8585e6241c42b598bcec554))

### Changed

- Align pins to v1.8.52 (1d689aa) ([6dbc8d2](https://github.com/y-miyazaki/config/commit/6dbc8d2b70137ea2f89f2c569c54524bdc7cba59))
- Finalize all pins v1.8.52 (ff0ef35) ([1d689aa](https://github.com/y-miyazaki/config/commit/1d689aa8bf3617c8927c76db3f2ec79f874d7986))
- Pin all to release v1.8.52 (4454282) ([ff0ef35](https://github.com/y-miyazaki/config/commit/ff0ef354f01b9108273706cae86c4343ded2fdd0))
- Pin all to v1.8.52 (8ae84dd) ([4454282](https://github.com/y-miyazaki/config/commit/445428208e6aa11e9a674bca0b6627ddfc4ff135))
- Promote state for PR #472 [skip ci] (loop) ([e7061cc](https://github.com/y-miyazaki/config/commit/e7061ccd8aaaa9c9be44cc414b5924096b530e20))
- Loop-automated update (attempt 1) (#472) ([3d35056](https://github.com/y-miyazaki/config/commit/3d350567184d89c43684044c28d6966e3ab7de71))
- Append run log [skip ci] (loop) ([23ce47d](https://github.com/y-miyazaki/config/commit/23ce47d25cfa2be55a357d2d4b06ed5c470ccdfd))
- Update state [skip ci] (loop) ([9ea2c3f](https://github.com/y-miyazaki/config/commit/9ea2c3f2393c859e2c7d31fda4d469546308374a))
- Streamline JSON configuration and update changelog references ([8f456d9](https://github.com/y-miyazaki/config/commit/8f456d92b31f5b55900355a2c26fee33adac3ec2))
- Append run log [skip ci] (loop) ([531f216](https://github.com/y-miyazaki/config/commit/531f2160d26cb08b2eeb0d9a9cbd965bd7129831))
- Append run log [skip ci] (loop) ([d9144fa](https://github.com/y-miyazaki/config/commit/d9144fa8ac54e56c794343b4f933000f6ba28c82))
- Append run log [skip ci] (loop) ([e1b623c](https://github.com/y-miyazaki/config/commit/e1b623caac58dc93857b47e35e55cf4e08966114))
- Append run log [skip ci] (loop) ([1668535](https://github.com/y-miyazaki/config/commit/1668535873cee9ac7ce01d1e8ff149ea22ea3022))
- Append run log [skip ci] (loop) ([d6f3334](https://github.com/y-miyazaki/config/commit/d6f3334daae553c8748a9cb18f5a0c78236d6671))
- Update state [skip ci] (loop) ([49f377f](https://github.com/y-miyazaki/config/commit/49f377fcafb1865861f6ce7d5bf3ddfe0ce5d22a))
- Update APM configuration and enhance hook definitions ([0a7a344](https://github.com/y-miyazaki/config/commit/0a7a344ca4e99a83a04b9f82ed12d709009b8751))
- Refactor script paths and enhance sync functionality ([3462a84](https://github.com/y-miyazaki/config/commit/3462a8400b06961a37dd319e7e5c5b79a38fa3bf))
- Append run log [skip ci] (loop) ([cbbf08f](https://github.com/y-miyazaki/config/commit/cbbf08ff736e3e486019a08e35ceefe7c9b02593))
- Update state [skip ci] (loop) ([af4b4dd](https://github.com/y-miyazaki/config/commit/af4b4dd0b3d7c833aa2fe0bf7492726a8cb24d42))
- Append run log [skip ci] (loop) ([302a674](https://github.com/y-miyazaki/config/commit/302a674479064271fe26cfab0900049f8fe79d82))
- Update state [skip ci] (loop) ([2737cb4](https://github.com/y-miyazaki/config/commit/2737cb4cbd1fa829b3c07745bb8231d989fa9cdf))

#### Dependencies

- Update dependency aqua:BurntSushi/ripgrep to v15.2.0 (#470) (mise) ([93c851c](https://github.com/y-miyazaki/config/commit/93c851c3361ea752d535499587479d4525f01fee))
- Update zizmor to v1.27.0 (#452) (zizmor) ([62ceacb](https://github.com/y-miyazaki/config/commit/62ceacb75c82e7af845563232815fc884f7dbfe6))
- Update dependency claude to v2.1.211 (#469) (mise) ([50ccd0b](https://github.com/y-miyazaki/config/commit/50ccd0be12ebf8c5994d3188ff0e12d1bc4281f2))
- Update dependency aqua:github/copilot-cli to v1.0.71 (#468) (mise) ([277351c](https://github.com/y-miyazaki/config/commit/277351c5bfff6e952472a22bc0cf2f66bf39f69f))
- Update zizmorcore/zizmor-action action to v0.6.0 (#463) (github-actions) ([ba5d045](https://github.com/y-miyazaki/config/commit/ba5d045c15d4b9991c7ede6cd050e0732af272b0))
- Update dependency aqua:aws/aws-cli to v2.35.24 (#467) (mise) ([bd1bf21](https://github.com/y-miyazaki/config/commit/bd1bf21922ee4ea53defa5ba3c81c30db2bb1346))
- Update dependency aqua:astral-sh/uv to v0.11.29 (#466) (mise) ([f33e3ca](https://github.com/y-miyazaki/config/commit/f33e3ca1826fa4d664abc3c823fbcea2f145ec0e))
- Update mise to v2026.7.7 (#465) (github-actions-tool-version) ([f1b8542](https://github.com/y-miyazaki/config/commit/f1b8542c9746221e12e90a5725a62e407c658991))
- Update dependency astral-sh/uv to v0.11.29 (#464) (github-actions-tool-version) ([fc55058](https://github.com/y-miyazaki/config/commit/fc550586f154a596290ee8ab525962abff066abb))

## [1.8.51] - 2026-07-22

### Changed

- Align pins to v1.8.51 (e6c9d54) ([eb1edc2](https://github.com/y-miyazaki/config/commit/eb1edc2b99fc4c9557ed103d68f680c270d5f4b7))
- Finalize all pins v1.8.51 (e8cd1d1) ([e6c9d54](https://github.com/y-miyazaki/config/commit/e6c9d54dd8acbc9f72e2ae78c735414e420aee50))
- Pin all to release v1.8.51 (2cee14b) ([e8cd1d1](https://github.com/y-miyazaki/config/commit/e8cd1d13621f2a5159e479f7b874c0d825479329))
- Pin all to v1.8.51 (39a1b1a) ([2cee14b](https://github.com/y-miyazaki/config/commit/2cee14b0251c1758bd1da6ae3e5cd08b687e3933))
- Update APM packages and improve script documentation (config) ([39a1b1a](https://github.com/y-miyazaki/config/commit/39a1b1af7ad269a4b0d3a72ebc1fb1d892a86d69))
- Append run log [skip ci] (loop) ([060a2f2](https://github.com/y-miyazaki/config/commit/060a2f25dd3da6dc96b8a46f541f22f163d964b3))
- Update state [skip ci] (loop) ([990cf72](https://github.com/y-miyazaki/config/commit/990cf723def6891a1ffc759365b4833d4e74a11a))
- Append run log [skip ci] (loop) ([d96d066](https://github.com/y-miyazaki/config/commit/d96d0668e329d0131d1dd26c9c6a3f88a86e7f39))
- Update state [skip ci] (loop) ([8d60b53](https://github.com/y-miyazaki/config/commit/8d60b538da1473b9f06e2767a3016ce42b0e8fe4))
- Append run log [skip ci] (#460) (loop) ([3c67296](https://github.com/y-miyazaki/config/commit/3c67296e95fbe1e4fa589d7b4c296cd15cb7d7a7))
- Append run log [skip ci] (loop) ([f25fce8](https://github.com/y-miyazaki/config/commit/f25fce8e347b1138dc97f419a4b0c9754e3f1787))
- Append run log [skip ci] (loop) ([53c8a9e](https://github.com/y-miyazaki/config/commit/53c8a9e517e54af672cbfbe2df1d45643e996767))
- Append run log [skip ci] (loop) ([32d831c](https://github.com/y-miyazaki/config/commit/32d831c0589ee5d9a1398b7858397094579ddf3c))

#### Dependencies

- Update dependency claude to v2.1.210 (#462) (mise) ([24be01d](https://github.com/y-miyazaki/config/commit/24be01d21d98e1b35d3b2075ec6906ddf7ab4a19))
- Update ecschedule to v0.20.0 (#459) (github-actions-tool-version) ([34875a4](https://github.com/y-miyazaki/config/commit/34875a4fa149cd39be16ffa0ae440b144331ca1e))
- Update dependency mcp-compressor to v0.31.6 (#461) (apm-mcp) ([b27c249](https://github.com/y-miyazaki/config/commit/b27c249a87946bd550217d8d4c50182a14551e47))
- Update dependency aqua:aws/aws-cli to v2.35.23 (#458) (mise) ([fef842f](https://github.com/y-miyazaki/config/commit/fef842f7209f9a2154a716a7c5d23a977138a837))

## [1.8.50] - 2026-07-21

### Changed

- Align pins to v1.8.50 (1bdad6b) ([bfd190c](https://github.com/y-miyazaki/config/commit/bfd190c986327be5ea82e728a0e3a28d5cd4e76c))
- Finalize all pins v1.8.50 (1fc140a) ([1bdad6b](https://github.com/y-miyazaki/config/commit/1bdad6bbbe6c0acd740551a08a05e7eb3231a9a8))
- Pin all to release v1.8.50 (9127118) ([1fc140a](https://github.com/y-miyazaki/config/commit/1fc140ad9623cdd9cd9f3f25e2bd2b47cb74d541))
- Pin all to v1.8.50 (52673a7) ([9127118](https://github.com/y-miyazaki/config/commit/912711873bb40763d617b8be25b2456b5355b32f))
- Append run log [skip ci] (loop) ([5c9def0](https://github.com/y-miyazaki/config/commit/5c9def0b2780408ea598e3beb61ff31715f8553c))
- Update state [skip ci] (loop) ([225c942](https://github.com/y-miyazaki/config/commit/225c942f44ac868628525513fe5c6c00351496f7))
- Append run log [skip ci] (loop) ([e39473f](https://github.com/y-miyazaki/config/commit/e39473f7b7261543c13ccf333e252f895c145aaf))
- Update state [skip ci] (loop) ([101bdff](https://github.com/y-miyazaki/config/commit/101bdff50605d35ee9806fd7b7ed684daa722aba))
- Append run log [skip ci] (loop) ([0faacc3](https://github.com/y-miyazaki/config/commit/0faacc328b3ada5af64493d211c104dc7c0a848d))
- Update state [skip ci] (loop) ([e7856c1](https://github.com/y-miyazaki/config/commit/e7856c127f9a7fb5b8b877545c9aa8f3ac790e6a))
- Append run log [skip ci] (loop) ([fafae94](https://github.com/y-miyazaki/config/commit/fafae94ef030690df1b4c68c3a554db0293bb2ab))
- Update state [skip ci] (loop) ([2dacfd2](https://github.com/y-miyazaki/config/commit/2dacfd22776cc062875c3b3105fd2132902c2a9a))

#### Dependencies

- Update mise to v2026.7.6 (#457) (github-actions-tool-version) ([dceda0c](https://github.com/y-miyazaki/config/commit/dceda0ca834292df7fbebe630c8d3860a24315a1))

## [1.8.49] - 2026-07-21

### Fixed

- Automated documentation update (loop-docs-triage) (#454) (docs) ([b558690](https://github.com/y-miyazaki/config/commit/b558690cd02ede418bb986a1f95c634004c31c24))

### Changed

- Align pins to v1.8.49 (b7dbe0b) ([4fc34e8](https://github.com/y-miyazaki/config/commit/4fc34e869ac8529d0413afdcad036b8236f91ea5))
- Finalize all pins v1.8.49 (0575b2a) ([b7dbe0b](https://github.com/y-miyazaki/config/commit/b7dbe0b8b43ebe4e476c2466c858fefd9b7728d9))
- Pin all to release v1.8.49 (a2326ee) ([0575b2a](https://github.com/y-miyazaki/config/commit/0575b2ab2981ecfab8ac1a60a19eefc602af6fc3))
- Pin all to v1.8.49 (d7b7565) ([a2326ee](https://github.com/y-miyazaki/config/commit/a2326ee2152e85a0dff0ec92470ebb096b6d6643))
- Update lockfile and script permissions (apm) ([d7b7565](https://github.com/y-miyazaki/config/commit/d7b756574c37ff64cce11bfac3c4b371946b2cbb))
- Append run log [skip ci] (loop) ([f8ce33b](https://github.com/y-miyazaki/config/commit/f8ce33b1de6e1389efdda3b18053f139f6e4199a))
- Update state [skip ci] (loop) ([a149643](https://github.com/y-miyazaki/config/commit/a1496431cbd69c4c674ea00a45f3fa933b714593))
- Append run log [skip ci] (loop) ([525ab27](https://github.com/y-miyazaki/config/commit/525ab2764e047ec08102c6ec11a335d3f69fc180))
- Update zizmor grouping rules and documentation (renovate) ([8f75ab0](https://github.com/y-miyazaki/config/commit/8f75ab05d70c43467a0a09d89f2b2693bc2786c1))
- Append run log [skip ci] (loop) ([e532bdb](https://github.com/y-miyazaki/config/commit/e532bdb2f7538a0e450756bb569e481db927e9ab))
- Update state [skip ci] (loop) ([aa798e1](https://github.com/y-miyazaki/config/commit/aa798e11d1087b5b0c9c88c5883eb58ba948e574))
- Append run log [skip ci] (loop) ([df8bdc9](https://github.com/y-miyazaki/config/commit/df8bdc9aa81671e866ff11d37cf2c562b44e9269))
- Update state [skip ci] (loop) ([f9ea5fe](https://github.com/y-miyazaki/config/commit/f9ea5fedcb297a7e87e1ad6455a735bfd6071524))
- Promote state for PR #454 [skip ci] (loop) ([dc22d59](https://github.com/y-miyazaki/config/commit/dc22d59eabdad1c7731e7b0986ccb7176dd938fe))
- Append run log [skip ci] (loop) ([30b9843](https://github.com/y-miyazaki/config/commit/30b984318e3e2d6cbd1481901db82acdf4a068b6))
- Update state [skip ci] (loop) ([d089e6d](https://github.com/y-miyazaki/config/commit/d089e6df82f07e4144285ca461699196dbef9e77))
- Append run log [skip ci] (loop) ([f899b72](https://github.com/y-miyazaki/config/commit/f899b729c39776d99ad27f9fed7851e6629a6f24))
- Update state [skip ci] (loop) ([6dca48d](https://github.com/y-miyazaki/config/commit/6dca48d255c77109b2d02f3fe1a38f1fffbca6fe))
- Append run log [skip ci] (loop) ([2aa5d17](https://github.com/y-miyazaki/config/commit/2aa5d177def42bed9cf1d64bb92563092310aff8))
- Update state [skip ci] (loop) ([2931fe4](https://github.com/y-miyazaki/config/commit/2931fe421ecfd40a14cbb8fc0c89e73dacc06afa))
- Clear_pending state for PR #450 [skip ci] (loop) ([e041de4](https://github.com/y-miyazaki/config/commit/e041de4dcbaa40415a4c5f1b3b3c842dc0c1c696))
- Append run log [skip ci] (loop) ([0f01f16](https://github.com/y-miyazaki/config/commit/0f01f16d68d8d67d1d0bffffa72a9fc1255f8a89))
- Update state [skip ci] (loop) ([14f40bd](https://github.com/y-miyazaki/config/commit/14f40bd3fc3cd0a4350771766c64fa51ba26db73))
- Update action references to v1.8.48 (af5d284) ([ca0af62](https://github.com/y-miyazaki/config/commit/ca0af6234d0d8aeaf5d2fb2c6504aef8081aa015))

#### Dependencies

- Update dependency aqua:jdx/usage to v3.5.5 (#456) (mise) ([cdd7507](https://github.com/y-miyazaki/config/commit/cdd75072a247a435c0e0fd4f6e6c5c458443dd9a))
- Update dependency claude to v2.1.209 (#451) (mise) ([b737fa5](https://github.com/y-miyazaki/config/commit/b737fa59fd337ebe3d7c91cf8a40a438e2cc0477))
- Update actions/setup-node action to v7 (#448) (github-actions) ([c9eb9a4](https://github.com/y-miyazaki/config/commit/c9eb9a4b03b7d5c1e5f0bdd457a01ffc5c7308d5))
- Update y-miyazaki/config digest to af5d284 (#449) (github-actions) ([b884389](https://github.com/y-miyazaki/config/commit/b884389531d8968726dcbd277d307de69f214d29))
- Update actions/setup-node action to v6.5.0 (#447) (github-actions) ([77547a4](https://github.com/y-miyazaki/config/commit/77547a4e93946b7fbf93a33a1a26a23a1e9b1c05))

## [1.8.48] - 2026-07-21

### Added

- Add loop-refactor skill and related assets (refactor) ([8b8ba4c](https://github.com/y-miyazaki/config/commit/8b8ba4c560e95fd8246d03108b4ed46257f298e9))
- Introduce new refactor skill and evaluation framework (refactor) ([8f48a8e](https://github.com/y-miyazaki/config/commit/8f48a8e5698d63c9239464881181afea357ce0ec))

### Changed

- Finalize all pins v1.8.48 (346d93b) ([af5d284](https://github.com/y-miyazaki/config/commit/af5d2849a2897c2bbfd13e54afb010a865c95b39))
- Pin all to release v1.8.48 (9c95ed1) ([346d93b](https://github.com/y-miyazaki/config/commit/346d93b0dd99c6a278e333b44e368cd73af1bbde))
- Pin all to v1.8.48 (265ae2d) ([9c95ed1](https://github.com/y-miyazaki/config/commit/9c95ed14ad9e0a739516e3f08524fa36cd68a7bb))
- Update apm.lock.yaml with new generated_at timestamp and updated file hashes ([265ae2d](https://github.com/y-miyazaki/config/commit/265ae2d318a819713d8e56d99e1d76ac5adab977))

#### Dependencies

- Update dependency claude to v2.1.208 (#446) (mise) ([2ca47f2](https://github.com/y-miyazaki/config/commit/2ca47f2fbbe95dbe1dd75f97ee9a192b77ef608d))
- Update dependency aqua:aws/aws-cli to v2.35.22 (#445) (mise) ([7de6741](https://github.com/y-miyazaki/config/commit/7de6741e30df21372cda7eb47b2262e0f8404477))

## [1.8.47] - 2026-07-20

### Changed

- Align pins to v1.8.47 (0563091) ([ee597b2](https://github.com/y-miyazaki/config/commit/ee597b2d62c99efb97239c27b385216c101632ea))
- Finalize all pins v1.8.47 (9a66be4) ([0563091](https://github.com/y-miyazaki/config/commit/0563091c60057dabde8167fbb6e00bf3453639fc))
- Pin all to release v1.8.47 (a70151a) ([9a66be4](https://github.com/y-miyazaki/config/commit/9a66be48d73f617e756dafdcfa105c1fc25fa167))
- Pin all to v1.8.47 (c45fee3) ([a70151a](https://github.com/y-miyazaki/config/commit/a70151a9a3ce078c8f8b1f2db6bb96c9313dd222))
- Update loop-changelog and loop-docs-triage evaluations ([c45fee3](https://github.com/y-miyazaki/config/commit/c45fee35a1345e33d430261aecce14c71c1d296f))
- Update apm.lock.yaml and remove deprecated code-review.md files ([3e50c7b](https://github.com/y-miyazaki/config/commit/3e50c7b4956be1e191cfc3080aa5ea5c55da2dfe))
- Promote state for PR #444 [skip ci] (loop) ([f3c22eb](https://github.com/y-miyazaki/config/commit/f3c22eb388822a7a82df0fd6ee9c3a2a45d75234))
- Loop-automated update (attempt 1) (#444) ([bb5a498](https://github.com/y-miyazaki/config/commit/bb5a498b49f8f434bf5a62985698a0bad32ee951))
- Append run log [skip ci] (loop) ([baa148f](https://github.com/y-miyazaki/config/commit/baa148fa70164476e4a2732d3c8f283130818df4))
- Update state [skip ci] (loop) ([5654baf](https://github.com/y-miyazaki/config/commit/5654bafa84caa03a035348e61330057038176160))
- Append run log [skip ci] (loop) ([23ae252](https://github.com/y-miyazaki/config/commit/23ae2529938a08c4a700b8c4d0c9990fe606a94c))
- Update state [skip ci] (loop) ([ed7332b](https://github.com/y-miyazaki/config/commit/ed7332be4724ddb3ffc84f2e5f25770c2d7ae923))
- Promote state for PR #443 [skip ci] (loop) ([abbecda](https://github.com/y-miyazaki/config/commit/abbecda5732f0e28e67749e60674fc200649b639))
- Loop-automated update (attempt 1) (#443) ([21e0e4b](https://github.com/y-miyazaki/config/commit/21e0e4b8770f2f7303ef251fb64ce710ebf0ef7f))
- Update gitleaks and golangci-lint configurations for clarity ([3c1b9f5](https://github.com/y-miyazaki/config/commit/3c1b9f5a0098fe77958f742b7c0ae620b6b615a1))
- Append run log [skip ci] (loop) ([bb0e13f](https://github.com/y-miyazaki/config/commit/bb0e13f826492a8cd89b0a62cfd2097177e266d6))
- Update state [skip ci] (loop) ([6b7731b](https://github.com/y-miyazaki/config/commit/6b7731bf836a9733148f420697e80c6bcf3aace0))

## [1.8.46] - 2026-07-20

### Added

- Introduce repository path filtering library (repo-paths) ([edf6ad8](https://github.com/y-miyazaki/config/commit/edf6ad8be692df5f940dbc0b68f79a381b9e215e))
- Enhance evaluation suite and update skill version (loop-tech-debt) ([1454ee0](https://github.com/y-miyazaki/config/commit/1454ee037f3810e62b46d7d700f0f5b4c74d86a9))
- Introduce loop-tech-debt skill and evaluation suite (loop-tech-debt) ([52f40b0](https://github.com/y-miyazaki/config/commit/52f40b01ae0f4cccb333b9608627c7a4da73ebb0))
- Detect git churn hotspots (loop-tech-debt) ([a1ccd14](https://github.com/y-miyazaki/config/commit/a1ccd1450b9c17922cefcecc4735a526604e1139))
- Detect broken links and stale docs (loop-tech-debt) ([5f87436](https://github.com/y-miyazaki/config/commit/5f87436d1c4fa40d8a691d895de42364c0f8f1be))
- Detect dependency version signals (loop-tech-debt) ([f757176](https://github.com/y-miyazaki/config/commit/f757176d26d1e4b462fa04ef567212009ebd6035))
- Detect TODO/FIXME/HACK/XXX marker signals (loop-tech-debt) ([980c5cf](https://github.com/y-miyazaki/config/commit/980c5cf68629c198e933b58168bc05b1c91dae23))
- Scaffold detect_tech_debt CLI and JSON contract (loop-tech-debt) ([a9905a5](https://github.com/y-miyazaki/config/commit/a9905a5cc3e86eaee4f5496e869a05da17c0c46c))

### Fixed

- Update references and improve clarity in workflow documentation (docs) ([a8a3420](https://github.com/y-miyazaki/config/commit/a8a3420551681aa56a9bb36653e68245a130f0ac))
- Require git repo and align classification eval (loop-tech-debt) ([822974d](https://github.com/y-miyazaki/config/commit/822974d9cf4a54df229e1ee9a5320055b9e7843a))
- Preserve mlc skip warnings outside subshell (loop-tech-debt) ([112cfc2](https://github.com/y-miyazaki/config/commit/112cfc20e58f634146369e6a52f17644eda1bbd7))
- Warn on mlc/jq failures and accurate stale_doc source (loop-tech-debt) ([6e3acaf](https://github.com/y-miyazaki/config/commit/6e3acaf027c84d7ef607a378704e23aae4e2da6e))
- Separate dependency signal caps from markers (loop-tech-debt) ([c5e233b](https://github.com/y-miyazaki/config/commit/c5e233b7339685421894393a30c9bcffcb9b1381))

### Changed

- Align pins to v1.8.46 (7466dbe) ([f62642e](https://github.com/y-miyazaki/config/commit/f62642e2ae2becc53dd10e1d5f4b54d7b278e653))
- Finalize all pins v1.8.46 (f239745) ([7466dbe](https://github.com/y-miyazaki/config/commit/7466dbe9ec68181e11c785572180b940b1e56b3c))
- Pin all to release v1.8.46 (231a3d8) ([f239745](https://github.com/y-miyazaki/config/commit/f23974535bc3a1916323e20082d289f1c582886e))
- Pin all to v1.8.46 (a8a3420) ([231a3d8](https://github.com/y-miyazaki/config/commit/231a3d8bde740d533d16f724ae18c5b5030e9074))
- Clear_pending state for PR #442 [skip ci] (loop) ([94f4b2e](https://github.com/y-miyazaki/config/commit/94f4b2e97f1358cd5b4d168b7641fa5f47bcd332))
- Append run log [skip ci] (loop) ([a704cf9](https://github.com/y-miyazaki/config/commit/a704cf9b3c173679c8454a2731a2bdef630ad478))
- Update state [skip ci] (loop) ([9da3405](https://github.com/y-miyazaki/config/commit/9da34057f4f01017f68c846938316f218e89dedf))
- Update APM version to 0.26.0 and enhance hook configurations (apm) ([93c5ba6](https://github.com/y-miyazaki/config/commit/93c5ba61340bf676673b257d5d6cb9c35c557791))
- Complete package manifest, evals, and design docs (loop-tech-debt) ([b196db6](https://github.com/y-miyazaki/config/commit/b196db643a01a801bb3bf48fe269e97d993052e4))
- Update schema, taxonomy, and checklist for detect (loop-tech-debt) ([de22088](https://github.com/y-miyazaki/config/commit/de22088904812e088370382b20a9381ad42663f9))

## [1.8.45] - 2026-07-19

### Changed

- Align pins to v1.8.45 (580c092) ([907ca7e](https://github.com/y-miyazaki/config/commit/907ca7ec4605a86db7e9a80c3a045879702dbdc4))
- Finalize all pins v1.8.45 (e4ec1d7) ([580c092](https://github.com/y-miyazaki/config/commit/580c092e719ab1d45b9fa7f19fda2ea6bef69d8f))
- Pin all to release v1.8.45 (cc094c7) ([e4ec1d7](https://github.com/y-miyazaki/config/commit/e4ec1d796ac406d26940329d1d99f16b8ec10c0a))
- Pin all to v1.8.45 (01d6d68) ([cc094c7](https://github.com/y-miyazaki/config/commit/cc094c789980dae42e8c7f5a89b0fd05bd1c4526))
- Update lean-ctx and related dependencies ([01d6d68](https://github.com/y-miyazaki/config/commit/01d6d683ccf6b0853c6d84b8f73b00f27b8754f9))

## [1.8.44] - 2026-07-19

### Changed

- Align pins to v1.8.44 (c1fa673) ([4531522](https://github.com/y-miyazaki/config/commit/45315228b203ce6709e476dc8c5cc8b6da42aceb))
- Finalize all pins v1.8.44 (e41943f) ([c1fa673](https://github.com/y-miyazaki/config/commit/c1fa67315e4c3b77c23526d019c5375ee151aeda))
- Pin all to release v1.8.44 (06cef2b) ([e41943f](https://github.com/y-miyazaki/config/commit/e41943f0781da872580069b6ef7463d617246e20))
- Pin all to v1.8.44 (8eee13d) ([06cef2b](https://github.com/y-miyazaki/config/commit/06cef2b8c5297dd3853f8fa050abb0b16dea3a13))
- Enhance loop actions with MCP support ([8eee13d](https://github.com/y-miyazaki/config/commit/8eee13dc89bf0edbe4c6317b01cfb1511956db46))

#### Dependencies

- Update dependency @upstash/context7-mcp to v3 (#439) (apm-mcp) ([09d7f81](https://github.com/y-miyazaki/config/commit/09d7f8105d5455217de2d5e83164524afcfa23e2))
- Update dependency mcp-server-fetch to v2026 (#440) (apm-mcp) ([af4ba84](https://github.com/y-miyazaki/config/commit/af4ba849ea0be6497fcb5251e6d37a92745fbd01))

## [1.8.43] - 2026-07-19

### Changed

- Align pins to v1.8.43 (803cb18) ([1d6c877](https://github.com/y-miyazaki/config/commit/1d6c877d83a263774185aeb66a281ac5ef20564a))
- Finalize all pins v1.8.43 (a65e52c) ([803cb18](https://github.com/y-miyazaki/config/commit/803cb1805788ec38018a16c44c26e2b01f6b95ef))
- Pin all to release v1.8.43 (6bd3eeb) ([a65e52c](https://github.com/y-miyazaki/config/commit/a65e52cdc0a5b24a0531a4fec98cb6ea91d30305))
- Pin all to v1.8.43 (a6980b2) ([6bd3eeb](https://github.com/y-miyazaki/config/commit/6bd3eebe01b551760c55a742c40dca315b84ec89))
- Enhance shell-script validation with Bats test integration (apm) ([185c642](https://github.com/y-miyazaki/config/commit/185c6429f4140cd89094de0bea250b87fab18666))
- Update lean-ctx and context7 dependencies in configuration files (apm) ([5bdeb27](https://github.com/y-miyazaki/config/commit/5bdeb27b0239ff0669796c41dc0cbbf399dffeb1))
- Update lockfile version and dependencies (apm) ([9710865](https://github.com/y-miyazaki/config/commit/97108653bae869e0b4ce269f5b41d0963daed3bb))
- Promote state for PR #433 [skip ci] (loop) ([8425ecf](https://github.com/y-miyazaki/config/commit/8425ecfd311ab628e551a4d92cb80327125eb267))
- Append run log [skip ci] (loop) ([8e9fe72](https://github.com/y-miyazaki/config/commit/8e9fe7297a5dd53bb289f881e33fdf2bdde4f891))
- Update state [skip ci] (loop) ([f0f527f](https://github.com/y-miyazaki/config/commit/f0f527f589771c3b84b76baac8025020451ac578))

#### Dependencies

- Update dependency aqua to v2.61.0 (#438) (mise) ([a6980b2](https://github.com/y-miyazaki/config/commit/a6980b2404c79ac86684d385db0ff11c9a81dc9b))
- Update dependency @upstash/context7-mcp to v2.3.0 (#437) (apm-mcp) ([8b7f093](https://github.com/y-miyazaki/config/commit/8b7f093d25acaf6fa2ffd7a988f270a36f194e9e))
- Update dependency awslabs.aws-pricing-mcp-server to v1.0.31 (#436) (apm-mcp) ([55f37f3](https://github.com/y-miyazaki/config/commit/55f37f30e1de0b1f38f85b7e762b2df67f75beeb))
- Update dependency awslabs.aws-documentation-mcp-server to v1.1.26 (#435) (apm-mcp) ([722822e](https://github.com/y-miyazaki/config/commit/722822e01a3d595ba0cd58df367b48423263c335))
- Update dependency github:yvgude/lean-ctx to v3.9.7 (#434) (mise) ([2f98286](https://github.com/y-miyazaki/config/commit/2f98286810a7b4ec4b59c6cc853baf793d10548d))

## [1.8.42] - 2026-07-18

### Changed

- Align pins to v1.8.42 (4a0df8b) ([a8506d6](https://github.com/y-miyazaki/config/commit/a8506d6d80b7a549a0e3c275448a33c7523cf343))
- Finalize all pins v1.8.42 (d03b884) ([4a0df8b](https://github.com/y-miyazaki/config/commit/4a0df8bd929df6eeddc8f1286bdda0ad129d11d7))
- Pin all to release v1.8.42 (429abd3) ([d03b884](https://github.com/y-miyazaki/config/commit/d03b884b2ba00d8e91a84aef0200ac00496ed381))
- Pin all to v1.8.42 (b3c5b32) ([429abd3](https://github.com/y-miyazaki/config/commit/429abd350af721a28749aebbaa398df126804734))
- Refine loop state management and update concurrency settings (loop) ([b3c5b32](https://github.com/y-miyazaki/config/commit/b3c5b322661ff3a9bab566925174cf9f67aa6319))
- Update state [skip ci] (loop) ([d840a1c](https://github.com/y-miyazaki/config/commit/d840a1c3ac0a803e45ecd91a1ec4935723a90c73))
- Remove unnecessary acting_on section from state-changelog.json ([d110ad3](https://github.com/y-miyazaki/config/commit/d110ad3c8dfcdf89235c6381f424b84af0bb7b07))

## [1.8.41] - 2026-07-18

### Changed

- Align pins to v1.8.41 (14ad6ed) ([fc3d096](https://github.com/y-miyazaki/config/commit/fc3d0965e4baba252989f166dc227190134e1f1f))
- Finalize all pins v1.8.41 (0bc0175) ([14ad6ed](https://github.com/y-miyazaki/config/commit/14ad6edf009a0a68817066c32fd7f95e79616ccf))
- Pin all to release v1.8.41 (9aef81c) ([0bc0175](https://github.com/y-miyazaki/config/commit/0bc01759c30fbf8087d4f38bcbb16133cf862371))
- Pin all to v1.8.41 (86ab318) ([9aef81c](https://github.com/y-miyazaki/config/commit/9aef81c9782dd70ef4d1942b1173cc9c747502bc))
- Enhance loop-finalize and loop-execute workflows for improved JSON handling and clarity ([86ab318](https://github.com/y-miyazaki/config/commit/86ab318be57040e8ef1cb94fa251eca5f28b9858))
- Update state [skip ci] (loop) ([28f2ae8](https://github.com/y-miyazaki/config/commit/28f2ae8a28528e28b3cf5b24025ddd60bd57f90a))

## [1.8.40] - 2026-07-18

### Added

- Enhance loop-detect and loop-execute workflows with improved error handling and output descriptions ([4d66c69](https://github.com/y-miyazaki/config/commit/4d66c694bfb699f50ca40e2cff614a3c8f1c2e0f))

### Changed

- Align pins to v1.8.40 (2c8c9ce) ([2b657e3](https://github.com/y-miyazaki/config/commit/2b657e364e67e28ee5e1313a51e4d20ab923782a))
- Finalize all pins v1.8.40 (5b3d244) ([2c8c9ce](https://github.com/y-miyazaki/config/commit/2c8c9ce50a31e97aeec3f32b06763bc1e2b23637))
- Pin all to release v1.8.40 (898575a) ([5b3d244](https://github.com/y-miyazaki/config/commit/5b3d2443c521bd09d34206c45f43730aad11787e))
- Pin all to v1.8.40 (4d66c69) ([898575a](https://github.com/y-miyazaki/config/commit/898575aae33d1b3c77f823deb318d760089ee753))

## [1.8.39] - 2026-07-18

### Added

- Implement loop-handoff artifact handling in loop-detect and loop-execute workflows ([eff0313](https://github.com/y-miyazaki/config/commit/eff03137fb3ada00f27b8db5d9a013db683b2411))

### Changed

- Align pins to v1.8.39 (9ba61b9) ([129fc9b](https://github.com/y-miyazaki/config/commit/129fc9b79f30515fcd4664c62cbe1f93f38e91cd))
- Finalize all pins v1.8.39 (636a084) ([9ba61b9](https://github.com/y-miyazaki/config/commit/9ba61b96a0ba594c92eb957fed74482547a96fe7))
- Pin all to release v1.8.39 (3dd22ac) ([636a084](https://github.com/y-miyazaki/config/commit/636a084035a840f04a6993daa42cb2666a4f338b))
- Pin all to v1.8.39 (eff0313) ([3dd22ac](https://github.com/y-miyazaki/config/commit/3dd22ac9191797b87994df71484568b1d42abe22))

## [1.8.38] - 2026-07-18

### Changed

- Align pins to v1.8.38 (7e0adb3) ([99d9bd1](https://github.com/y-miyazaki/config/commit/99d9bd12fb971d644fea1fb88783a398aedcec8f))
- Finalize all pins v1.8.38 (da75e13) ([7e0adb3](https://github.com/y-miyazaki/config/commit/7e0adb3e57ad6674028134e05e8cf33aef4e4fd5))
- Pin all to release v1.8.38 (a468234) ([da75e13](https://github.com/y-miyazaki/config/commit/da75e133fa9dd70754c3f0122e8e9f02f60d77ed))
- Pin all to v1.8.38 (ebb7197) ([a468234](https://github.com/y-miyazaki/config/commit/a4682345686aafa2443f6a8b4044e0c739d3ac0b))
- Update build_loop_candidate_json and enrich_target_json_with_ci_context functions to use temporary files for jq processing and improve error handling ([ebb7197](https://github.com/y-miyazaki/config/commit/ebb7197da8cf5306a36dc5a865cf7c4519bad6dd))

#### Dependencies

- Update dependency claude to v2.1.207 (#431) (mise) ([922686f](https://github.com/y-miyazaki/config/commit/922686f7d1c5b76e5308eeebf3e7bb0b313aaf70))
- Update dependency github:yvgude/lean-ctx to v3.9.6 (#430) (mise) ([94e04a7](https://github.com/y-miyazaki/config/commit/94e04a7f13055e7d33cf704ba8af92f10d72b747))
- Update dependency github:microsoft/apm to v0.24.1 (#429) (mise) ([13d8d25](https://github.com/y-miyazaki/config/commit/13d8d25e8a66f2c915e808725dddde889868d815))
- Update dependency aqua:aws/aws-cli to v2.35.21 (#428) (mise) ([c4fd431](https://github.com/y-miyazaki/config/commit/c4fd431cd6cc80f2c156c35669f49abef13580fe))

## [1.8.37] - 2026-07-17

### Fixed

- Restore heading level for CI Sweeper Test to ensure lint compliance (docs) ([6d01b6c](https://github.com/y-miyazaki/config/commit/6d01b6c115473c5447f77fb3410ff74affb7713f))

### Changed

- Align pins to v1.8.37 (1f0b8eb) ([79bec97](https://github.com/y-miyazaki/config/commit/79bec97381f7b5d64448900f72487dac22457964))
- Finalize all pins v1.8.37 (041e469) ([1f0b8eb](https://github.com/y-miyazaki/config/commit/1f0b8eb1e74a8e0b12bb6c2cfc71b92071084e48))
- Pin all to release v1.8.37 (ad318c5) ([041e469](https://github.com/y-miyazaki/config/commit/041e46905396e645ac7557174249c6814bc54e5d))
- Pin all to v1.8.37 (c82a069) ([ad318c5](https://github.com/y-miyazaki/config/commit/ad318c5b796262edd68a1ca3ad670350604c144a))
- Remove CI Sweeper Test markdown file as it is no longer needed (docs) ([c82a069](https://github.com/y-miyazaki/config/commit/c82a06942d1299e640911e4dcac6c173b2e4ab7d))
- Promote state for PR #427 [skip ci] (loop) ([5fabd42](https://github.com/y-miyazaki/config/commit/5fabd4262fa1f16c9b4c6e9af3a5a468e335c726))
- Loop-automated update (attempt 1) (#427) ([d065fe2](https://github.com/y-miyazaki/config/commit/d065fe2d1686f0c4b7a13c05d7bd8cd2c5c51d0e))
- Promote state for PR #426 [skip ci] (loop) ([b4bf443](https://github.com/y-miyazaki/config/commit/b4bf443237197ff22f75b9dadbdd993e1cd73590))
- Loop-automated update (attempt 1) (#426) ([8fed37d](https://github.com/y-miyazaki/config/commit/8fed37d746d6d4e4c8160bcaa576cf6fcf826a19))
- Update retention policy for state targets and run ledger to 30 days (loop) ([16e9520](https://github.com/y-miyazaki/config/commit/16e9520d540f0184ecc6ac448c609cf33fce0f2e))
- Append run log [skip ci] (loop) ([927c3d5](https://github.com/y-miyazaki/config/commit/927c3d501585a9ecfad909c04ba106753dda0868))
- Update state [skip ci] (loop) ([ccb2354](https://github.com/y-miyazaki/config/commit/ccb2354f7fa03482dc547e80e8cafc8afecd9cec))
- Update state [skip ci] (loop) ([b20d8ec](https://github.com/y-miyazaki/config/commit/b20d8ec37922f6d0986c7ad33e299c8e5ae98682))
- Append run log [skip ci] (loop) ([974f94d](https://github.com/y-miyazaki/config/commit/974f94d44f751604ff586f6bcabff2e33747533d))
- Update state [skip ci] (loop) ([7969fd6](https://github.com/y-miyazaki/config/commit/7969fd6d5d1b0f2e6092d079e1bf3aa1c51d6c1c))
- Update state [skip ci] (loop) ([29b61b9](https://github.com/y-miyazaki/config/commit/29b61b9429d69c4ec9ce2650be30a9e98ea0641a))
- Promote state for PR #425 [skip ci] (loop) ([f76d614](https://github.com/y-miyazaki/config/commit/f76d614f5b465397fc3a3a21616bf228542d01af))
- Loop-automated update (attempt 1) (#425) ([f73b703](https://github.com/y-miyazaki/config/commit/f73b7036f1f18112d7771fd9c252a90988e14f5c))

## [1.8.36] - 2026-07-17

### Changed

- Align pins to v1.8.36 (e9f7e78) ([a6fd278](https://github.com/y-miyazaki/config/commit/a6fd278ea6ba23f4eb7f59c86ed3514d08699189))
- Finalize all pins v1.8.36 (de4f533) ([e9f7e78](https://github.com/y-miyazaki/config/commit/e9f7e78c864e2bcdc0ed724ea718573f9ff4df55))
- Pin all to release v1.8.36 (663a0fa) ([de4f533](https://github.com/y-miyazaki/config/commit/de4f5337e3a5e1ca8f940b2e8af0e8c06d3c2d92))
- Pin all to v1.8.36 (982a508) ([663a0fa](https://github.com/y-miyazaki/config/commit/663a0facdfaefcb90a11bcb28596aedeab4a1307))
- Enhance notify_context and create_pr_body scripts for improved JSON handling and diff calculations (loop) ([982a508](https://github.com/y-miyazaki/config/commit/982a508d5c0da5ed62b1954968d084d272af950b))
- Append run log [skip ci] (loop) ([aba5f54](https://github.com/y-miyazaki/config/commit/aba5f54c5e043240f79f62ac696700101aa428bd))
- Update state [skip ci] (loop) ([cc0dc48](https://github.com/y-miyazaki/config/commit/cc0dc48f38d491ee44dc1ad0ff04e94f3bb87a71))
- Update state [skip ci] (loop) ([56b9b8e](https://github.com/y-miyazaki/config/commit/56b9b8ee503a71adbd41234bf72e2e83c62a2bba))
- Update heading level in CI Sweeper Test documentation for lint compliance ([81d0aa8](https://github.com/y-miyazaki/config/commit/81d0aa886aa07e52e533c338902c0aa480683ac2))

## [1.8.35] - 2026-07-17

### Changed

- Align pins to v1.8.35 (3373cba) ([d06d196](https://github.com/y-miyazaki/config/commit/d06d19646570abb849987552c0df528c5ca41f68))
- Finalize all pins v1.8.35 (a25657c) ([3373cba](https://github.com/y-miyazaki/config/commit/3373cba072024c0883ccc3ebe38da46c481118f2))
- Pin all to release v1.8.35 (27db91b) ([a25657c](https://github.com/y-miyazaki/config/commit/a25657c15359fd518a5bf24f433a999d98f161cc))
- Pin all to v1.8.35 (0444696) ([27db91b](https://github.com/y-miyazaki/config/commit/27db91b96e1cd7144d7c6f9d22abad17a55cfb84))
- Align pins to v1.8.35 (afac8e4) ([0444696](https://github.com/y-miyazaki/config/commit/044469656dec3ed550de362c5619ada3b4da1788))
- Finalize all pins v1.8.35 (4fcde27) ([281cec8](https://github.com/y-miyazaki/config/commit/281cec8e6422573ef61b303311b4046067c724d9))
- Pin all to release v1.8.35 (e4f04bb) ([eee78f5](https://github.com/y-miyazaki/config/commit/eee78f55762a8299de7b52f1902acb43d3e16715))
- Pin all to v1.8.35 (39ddcd7) ([ba11b20](https://github.com/y-miyazaki/config/commit/ba11b20309e2082617a2b6173182a1403b9ff1d9))
- Update pending PR handling in loop-detect actions and enhance documentation for clarity (loop) ([39ddcd7](https://github.com/y-miyazaki/config/commit/39ddcd7e1c260db0f1d1ad6cc0c064d56dc53830))
- Increase max runs per day for CI sweeper from 10 to 50 (loop) ([850904e](https://github.com/y-miyazaki/config/commit/850904e2172730b95b8e3259bb8dd5ad6f52c283))
- Append run log [skip ci] (loop) ([50b395e](https://github.com/y-miyazaki/config/commit/50b395e79e67bdc2852545b5509b609a3d49ea66))
- Standardize agent implementer model description across workflow documentation (workflows) ([d3e0e10](https://github.com/y-miyazaki/config/commit/d3e0e10963bf439bf80c3eb4ccaed0e7f3d78629))
- Update agent implementer model to cursor-grok-4.5-low across multiple workflow files (workflows) ([0e3fbe5](https://github.com/y-miyazaki/config/commit/0e3fbe5c19853a4e4423ec38832921ec0f6f6ef0))
- Append run log [skip ci] (loop) ([0689f7b](https://github.com/y-miyazaki/config/commit/0689f7b24ef9a02e8f8caef7e37c46651c6b0ca9))
- Add CI Sweeper Test markdown file with intentional lint failures for testing ([568a3b4](https://github.com/y-miyazaki/config/commit/568a3b411ba75ef776a84d23e708489443fca7cb))

#### Dependencies

- Update dependency github:yvgude/lean-ctx to v3.9.5 (#424) (mise) ([ffdb638](https://github.com/y-miyazaki/config/commit/ffdb63846d068ed81f8dde9130aaa03f9318e047))
- Update dependency pnpm to v11.11.0 (#419) (mise) ([3c25c16](https://github.com/y-miyazaki/config/commit/3c25c16e80a66c24f9c49d1555b6471359d670d9))

## [1.8.34] - 2026-07-17

### Changed

- Align pins to v1.8.34 (9387019) ([c3c6770](https://github.com/y-miyazaki/config/commit/c3c6770d88a5cf5031f34fb352ebb63154237483))
- Finalize all pins v1.8.34 (52504b6) ([9387019](https://github.com/y-miyazaki/config/commit/938701916a57f5f1f482bc2ddab9da3b2e5e91b3))
- Pin all to release v1.8.34 (7f0a619) ([52504b6](https://github.com/y-miyazaki/config/commit/52504b6a518baf7e7773d04f7cbe719d60c399c1))
- Pin all to v1.8.34 (f8bce82) ([7f0a619](https://github.com/y-miyazaki/config/commit/7f0a6194ae4f402522f2d24893e9093ca3d75d8c))
- Append run log [skip ci] (#421) (loop) ([f8bce82](https://github.com/y-miyazaki/config/commit/f8bce821a461ac5b0a02db554b690d9c142fb62c))
- Append run log [skip ci] (#423) (loop) ([7dd4480](https://github.com/y-miyazaki/config/commit/7dd4480b055e52074555f4f30ba56ced52727947))
- Append run log [skip ci] (#422) (loop) ([f5b9a66](https://github.com/y-miyazaki/config/commit/f5b9a667432239607f0c100bb3d76248c3210885))
- Append run log [skip ci] (loop) ([93d45b4](https://github.com/y-miyazaki/config/commit/93d45b4809422328076ee191c078bed5826f4e09))
- Append run log [skip ci] (loop) ([72292af](https://github.com/y-miyazaki/config/commit/72292afc7a062d7c615343ddb8eeabd1ec28a911))
- Append run log [skip ci] (loop) ([7e9f56e](https://github.com/y-miyazaki/config/commit/7e9f56ea626e660c92fe9557a29b62fe8625f77c))
- Append run log [skip ci] (loop) ([3a2d594](https://github.com/y-miyazaki/config/commit/3a2d594b8d4893fce5db8a9ecef413d70307c2cf))

## [1.8.33] - 2026-07-17

### Changed

- Append run log [skip ci] (loop) ([eea103d](https://github.com/y-miyazaki/config/commit/eea103d45241265498bea0027bdd0357b49cdfdb))
- Clear_pending state for PR #416 [skip ci] (loop) ([f3c0355](https://github.com/y-miyazaki/config/commit/f3c03559f1178ddeca1e764e5d1d644150fde2e5))
- Append run log [skip ci] (loop) ([e471320](https://github.com/y-miyazaki/config/commit/e471320e895faccea194fdc3e89bb134483ed8d7))
- Update state [skip ci] (loop) ([b00e12d](https://github.com/y-miyazaki/config/commit/b00e12dc59ca82aa347afdec5111c848eede8320))
- Update state [skip ci] (loop) ([9024b44](https://github.com/y-miyazaki/config/commit/9024b447571162cd238494d47812983bf2e275d4))
- Add reversed link syntax example to CI Sweeper Test documentation ([87ad883](https://github.com/y-miyazaki/config/commit/87ad883c8f31e69c592521a835ddfb8c0899b644))
- Append run log [skip ci] (loop) ([64b7ded](https://github.com/y-miyazaki/config/commit/64b7dedc4e1a40c0f447233233dc9c2e161077fe))
- Update state [skip ci] (loop) ([f046fe6](https://github.com/y-miyazaki/config/commit/f046fe69ed3f8dd36fd56b61cf82cf3cd404f76b))

#### Dependencies

- Update dependency github:yvgude/lean-ctx to v3.9.4 (#418) (mise) ([44cb198](https://github.com/y-miyazaki/config/commit/44cb19869475c5f54768775937e9939f45044806))

## [1.8.32] - 2026-07-17

### Added

- Enhance detection logic with scoped head branch support (loop-detect) ([5e5d12f](https://github.com/y-miyazaki/config/commit/5e5d12faf4b3885c24149c2232793612164dc8b6))
- Add markdown link check configuration and update checksums in lockfile ([9d32136](https://github.com/y-miyazaki/config/commit/9d321360ff992f27fe855bbdac63ef4a42c251bd))

### Changed

- Align pins to v1.8.32 (7a51271) ([cc768d3](https://github.com/y-miyazaki/config/commit/cc768d3ffd34d21a1e6f17f42c5fce01af9412eb))
- Finalize all pins v1.8.32 (365a11e) ([7a51271](https://github.com/y-miyazaki/config/commit/7a51271120c6ab965a606d86d3cc4dbad8922477))
- Pin all to release v1.8.32 (11168cd) ([365a11e](https://github.com/y-miyazaki/config/commit/365a11ee0b4e4ecce364d84279c48cfc1a3be777))
- Pin all to v1.8.32 (3eb752d) ([11168cd](https://github.com/y-miyazaki/config/commit/11168cd8c77cf8c4d54320d51ef84decb49bc147))
- Clear_pending state for PR #415 [skip ci] (loop) ([3eb752d](https://github.com/y-miyazaki/config/commit/3eb752d9df00bb257bab35c1551cd4746f1d0ce2))
- Append run log [skip ci] (loop) ([0cd3a62](https://github.com/y-miyazaki/config/commit/0cd3a62d4251d645ac5f58f31020015fc9e145e6))
- Update state [skip ci] (loop) ([dc4ed1a](https://github.com/y-miyazaki/config/commit/dc4ed1a05b9dadca77c8faeddb8932dad94bc81e))
- Append run log [skip ci] (loop) ([a76a10d](https://github.com/y-miyazaki/config/commit/a76a10d40d8ff6639b0c072291d0395553a72978))
- Update state [skip ci] (loop) ([45deea6](https://github.com/y-miyazaki/config/commit/45deea61534e15900389fcee953f6d0490dac894))
- Update state [skip ci] (loop) ([f3ff7c2](https://github.com/y-miyazaki/config/commit/f3ff7c233194f7657649ae19e6cb8443aed5703c))
- Add CI Sweeper Test markdown file for dogfood testing ([bd64af5](https://github.com/y-miyazaki/config/commit/bd64af5ffbe73498aa7442cc6315045c238f1e99))
- Update lockfile with new generated timestamps and updated script checksums ([0fa1e4a](https://github.com/y-miyazaki/config/commit/0fa1e4af81f64ac71d75c9b8dd89891eb28c6687))

#### Dependencies

- Update dependency pipx:headroom-ai to v0.31.0 (#409) (mise) ([7a18340](https://github.com/y-miyazaki/config/commit/7a1834060acfb22e4711649dfcf7e16f9b25cf7b))
- Update dependency claude to v2.1.206 (#414) (mise) ([7fe2ce4](https://github.com/y-miyazaki/config/commit/7fe2ce44c41672989003859670b2c45b4b25f6d6))
- Update dependency aqua:github/copilot-cli to v1.0.70 (#413) (mise) ([4c886c9](https://github.com/y-miyazaki/config/commit/4c886c949807b8899daa9b16bb9e18fb6df53581))

## [1.8.31] - 2026-07-17

### Changed

- Align pins to v1.8.31 (73d74ce) ([4e116d9](https://github.com/y-miyazaki/config/commit/4e116d994437398ce74580f4de6f779d2662da36))
- Finalize all pins v1.8.31 (4f3ef86) ([73d74ce](https://github.com/y-miyazaki/config/commit/73d74ce12720bcad2e95b56c30cf475d2a7e751a))
- Pin all to release v1.8.31 (cf5428b) ([4f3ef86](https://github.com/y-miyazaki/config/commit/4f3ef86bd5699872523e0e3a80985320db4a46bd))
- Pin all to v1.8.31 (ece3e47) ([cf5428b](https://github.com/y-miyazaki/config/commit/cf5428b7f8ec2b9bf4b052bc8517ee45cb9c8e35))
- Append run log [skip ci] (loop) ([e21a326](https://github.com/y-miyazaki/config/commit/e21a3261a8b5efa11e3374a74a48455836ce13f1))
- Update state [skip ci] (loop) ([92a9a3e](https://github.com/y-miyazaki/config/commit/92a9a3e0b39ae76ddd96c93d0000d72af552208c))
- Update state [skip ci] (loop) ([7096e12](https://github.com/y-miyazaki/config/commit/7096e12b0e58d7082ed39306684e4d3eacf683d8))
- Update state [skip ci] (loop) ([2c7d03b](https://github.com/y-miyazaki/config/commit/2c7d03b77b6ffdb397cd8f6f22920e23ef261eac))
- Update state [skip ci] (loop) ([dca0bd4](https://github.com/y-miyazaki/config/commit/dca0bd47ec6e9b270f0622bb5605dae235c88260))
- Clear_pending state for PR #406 [skip ci] (loop) ([069c8a1](https://github.com/y-miyazaki/config/commit/069c8a15b30e894691aa4887fcab8300fc782141))
- Clear_pending state for PR #407 [skip ci] (loop) ([8d369ae](https://github.com/y-miyazaki/config/commit/8d369aed9e27ad19d4925a1198d452ba967c563a))

#### Dependencies

- Update dependency aqua to v2.60.2 (#412) (mise) ([e3ed505](https://github.com/y-miyazaki/config/commit/e3ed5059ca55f401fbc10c1ce58c1490460d2974))
- Update mise to v2026.7.5 (#411) (github-actions-tool-version) ([c993d15](https://github.com/y-miyazaki/config/commit/c993d159232795c76da0ccfba9a0c34855be6c15))
- Update dependency aqua:aws/aws-cli to v2.35.20 (#410) (mise) ([33ec3b2](https://github.com/y-miyazaki/config/commit/33ec3b262ad82be59e83e7f72f7b46bba62a4491))
- Update mise to v2026.7.4 (#408) (github-actions-tool-version) ([96d6ac1](https://github.com/y-miyazaki/config/commit/96d6ac1a8cc3e6f185856c89a230bd36c2b68807))

## [1.8.30] - 2026-07-16

### Changed

- Update dependencies to version 1.8.29 across various workflows and configuration files, including changes to AWS MCP command execution method and documentation updates for OAuth integration. This ensures consistency and reflects the latest improvements in the project. ([0098282](https://github.com/y-miyazaki/config/commit/0098282039f73bf3aba3a67a02568c0dec11c2a5))

## [1.8.29] - 2026-07-16

### Changed

- Update AWS MCP configuration to use bash for command execution and remove deprecated awslabs-aws-api-mcp-server. Adjust documentation to reflect these changes and clarify the adoption of AWS MCP as the primary API operation tool. ([45afa9c](https://github.com/y-miyazaki/config/commit/45afa9c0f1dd5b8227bfd9efc86345fd45b0e65c))

## [1.8.28] - 2026-07-16

### Changed

- Align pins to v1.8.28 (7b0e855) ([23aab56](https://github.com/y-miyazaki/config/commit/23aab5619704545acaed28993f57424c9d8871d7))
- Finalize all pins v1.8.28 (918e16a) ([7b0e855](https://github.com/y-miyazaki/config/commit/7b0e8557d0544acef512cb7e5e81f96abf19bd44))
- Pin all to release v1.8.28 (c805e7f) ([918e16a](https://github.com/y-miyazaki/config/commit/918e16aeda601e99b06c7d119ad6fe8a834c9b26))
- Pin all to v1.8.28 (b0b0883) ([c805e7f](https://github.com/y-miyazaki/config/commit/c805e7f2236741af7eac11f0e83ca3ccd1d0eba9))
- Standardize PR handling configurations and enhance notification features (loop) ([b0b0883](https://github.com/y-miyazaki/config/commit/b0b0883e3f5b2d0708cb441a6808fb78030becc9))
- Append run log [skip ci] (loop) ([4c389fe](https://github.com/y-miyazaki/config/commit/4c389fe0fb356672e67b534cfb7b20ebe10d0e94))
- Update state [skip ci] (loop) ([0ca2f14](https://github.com/y-miyazaki/config/commit/0ca2f1464818a713c543aacb987aecffbe93274c))
- Update state [skip ci] (loop) ([1875e9b](https://github.com/y-miyazaki/config/commit/1875e9bfd50ea4a6a582f39c3f02898c1005533f))
- Update loop caller configuration and finalize strategies for PR handling (loop) ([625e178](https://github.com/y-miyazaki/config/commit/625e1787e4f77c66b9cdbad51aefe52f8e1edcbf))
- Append run log [skip ci] (loop) ([861fb08](https://github.com/y-miyazaki/config/commit/861fb08764c735ef9b2e35e40ad9623edfada160))
- Update state [skip ci] (loop) ([d6f041b](https://github.com/y-miyazaki/config/commit/d6f041b82e51e28f4dd2ec714760a645fcb6999e))
- Update state [skip ci] (loop) ([6f6f07c](https://github.com/y-miyazaki/config/commit/6f6f07ccf6f3094c17be2bbb26ff4e17f92509c5))
- Append run log [skip ci] (loop) ([f87b61d](https://github.com/y-miyazaki/config/commit/f87b61d9c264309459a04b1769942bc26a3c3455))
- Update state [skip ci] (loop) ([8db6661](https://github.com/y-miyazaki/config/commit/8db6661438e4afa5a97570b109c827c7f11884b7))
- Update state [skip ci] (loop) ([8972963](https://github.com/y-miyazaki/config/commit/89729633bc9e3ff06fcf1e03e991cda2e53fb501))

## [1.8.27] - 2026-07-16

### Changed

- Align pins to v1.8.27 (918db24) ([35953d5](https://github.com/y-miyazaki/config/commit/35953d539383a4f5503772f47a73c5c7c6853481))
- Finalize all pins v1.8.27 (33508f1) ([918db24](https://github.com/y-miyazaki/config/commit/918db24bc160b02462748456a742eba08c78cbf0))
- Pin all to release v1.8.27 (e043354) ([33508f1](https://github.com/y-miyazaki/config/commit/33508f1dc107530fb90b4401e0a033e6efa3079f))
- Pin all to v1.8.27 (47f3fb5) ([e043354](https://github.com/y-miyazaki/config/commit/e0433542c1084203d5684f97f593346186e391fa))

## [1.8.26] - 2026-07-16

### Fixed

- Set git identity on push_head finalize and fix notify trap (#404) (loop) ([86080c9](https://github.com/y-miyazaki/config/commit/86080c96bb7a03745719a81205b693bff6906e4c))
- Scope concurrency group per workflow_run id (#403) (ci-sweeper) ([fb54ce0](https://github.com/y-miyazaki/config/commit/fb54ce0bbe13f3c8cfdd48f9f44115f5bb1ef123))
- Escape JSON braces in detect_domain_env_json format() (#402) (ci-sweeper) ([dcbfd3d](https://github.com/y-miyazaki/config/commit/dcbfd3d37726b1daaca55a83fe3025e0bedbed08))

### Changed

- Align pins to v1.8.26 (f2c4021) ([47f3fb5](https://github.com/y-miyazaki/config/commit/47f3fb54aa5eda88b51ec09e003608a82fa51278))
- Finalize all pins v1.8.26 (179c4a3) ([f2c4021](https://github.com/y-miyazaki/config/commit/f2c4021e7dbe45f824eaf46d86641a3ff6624979))
- Pin all to release v1.8.26 (ce70870) ([179c4a3](https://github.com/y-miyazaki/config/commit/179c4a3d75aff08f72f6083131dfbb98803243e6))
- Pin all to v1.8.26 (13975e8) ([ce70870](https://github.com/y-miyazaki/config/commit/ce70870e6b5943030c3193a59972616f0d9b644c))
- Align pins to v1.8.27 (ecb346a) ([13975e8](https://github.com/y-miyazaki/config/commit/13975e897b6ccbada17ded542e7568f63daa6fa1))
- Finalize all pins v1.8.27 (cf11d87) ([8fa45bb](https://github.com/y-miyazaki/config/commit/8fa45bb95ac8a3b7f57118fd6ff7cd1788db5487))
- Pin all to release v1.8.27 (9834099) ([77ffacd](https://github.com/y-miyazaki/config/commit/77ffacd257f3472e1c4ed063e55a5a3af03d4882))
- Pin all to v1.8.27 (86080c9) ([93d9638](https://github.com/y-miyazaki/config/commit/93d9638ed0bd25e373ae56c9fe92d7ee1c48acd6))
- Update state [skip ci] (loop) ([5a950a0](https://github.com/y-miyazaki/config/commit/5a950a0133486ea2fa9ac924b77761476a6bd557))
- Update state [skip ci] (loop) ([c2e7efb](https://github.com/y-miyazaki/config/commit/c2e7efb76844757114b509bb880881c655c98ad8))
- Update state [skip ci] (loop) ([31ff768](https://github.com/y-miyazaki/config/commit/31ff768e91e64faa7974e6c953f5073bbc3ad213))
- Update state [skip ci] (loop) ([04a2319](https://github.com/y-miyazaki/config/commit/04a2319ba105d0200f640aa835099094831efa05))
- Update state [skip ci] (loop) ([fb8a669](https://github.com/y-miyazaki/config/commit/fb8a6694995e652068e48088cb90af32adcb9e13))
- Update state [skip ci] (loop) ([41a1875](https://github.com/y-miyazaki/config/commit/41a1875a17cf2baf2def445cc5bceffb714367fa))
- Update state [skip ci] (loop) ([940683d](https://github.com/y-miyazaki/config/commit/940683d775cfb86f4cafade6d16a0644d5a0e542))
- Align pins to v1.8.26 (0ae1c02) ([3743990](https://github.com/y-miyazaki/config/commit/374399044ebd57ed070290924f5e2205d4fc751a))
- Finalize all pins v1.8.26 (c587cbf) ([0ae1c02](https://github.com/y-miyazaki/config/commit/0ae1c021964530c4bf7e0f1e9f3ba78e422d32a9))
- Pin all to release v1.8.26 (ac9b8d7) ([c587cbf](https://github.com/y-miyazaki/config/commit/c587cbf767dedadc7a61f993d3cdd092e6421f91))
- Pin all to v1.8.26 (7fc465f) ([ac9b8d7](https://github.com/y-miyazaki/config/commit/ac9b8d75db3a25ddbe6430fbc229ac514a8ef81f))
- Reorganize loop engineering documentation and workflows ([1764dca](https://github.com/y-miyazaki/config/commit/1764dcaaa3aa2b361b2255b3b155237883520529))
- Clean up apm-hooks and settings configuration ([59125dc](https://github.com/y-miyazaki/config/commit/59125dc90f28eab925c69f6bb5940030faea25ec))

#### Dependencies

- Update dependency github:DeusData/codebase-memory-mcp to v0.9.0 (#395) (mise) ([70c7779](https://github.com/y-miyazaki/config/commit/70c7779102967ae9c628b017d6e880470f291523))
- Update dependency claude to v2.1.205 (#400) (mise) ([e4aa672](https://github.com/y-miyazaki/config/commit/e4aa672051e6c8b3fbaba72aa42441cb56b48fd5))
- Update dependency aqua:aws/aws-cli to v2.35.19 (#399) (mise) ([3526acb](https://github.com/y-miyazaki/config/commit/3526acbc03d8e1f93c830bf32bf09d2f0a0b2c46))
- Update terraform to v1.15.8 (#398) (terraform) ([295d387](https://github.com/y-miyazaki/config/commit/295d387a5e18c2ac7aba350c129a502e46c994ed))
- Update dependency aqua:aws/aws-cli to v2.35.18 (#397) (mise) ([211b25f](https://github.com/y-miyazaki/config/commit/211b25f83291c06940fc19a70a257525b033a39a))
- Update mise to v2026.7.3 (#396) (github-actions-tool-version) ([19284d5](https://github.com/y-miyazaki/config/commit/19284d577ee45b1647c060492c246fe9dc59e42d))

## [1.8.25] - 2026-07-15

### Changed

- Align pins to v1.8.25 (175b15b) ([72f4607](https://github.com/y-miyazaki/config/commit/72f4607806a44f3dec515526da1012271c14379d))
- Finalize all pins v1.8.25 (3de8f8a) ([175b15b](https://github.com/y-miyazaki/config/commit/175b15b5ccc689524c9370247597666446007cc8))
- Pin all to release v1.8.25 (097c069) ([3de8f8a](https://github.com/y-miyazaki/config/commit/3de8f8a241ead56612f2436297d90cc114df7014))
- Pin all to v1.8.25 (7cbcd01) ([097c069](https://github.com/y-miyazaki/config/commit/097c069ac1f3efd659479adb74395b997ae06eb8))
- Append run log [skip ci] (loop) ([b738cdb](https://github.com/y-miyazaki/config/commit/b738cdbcbfdfd3686abbfe18dbb3fe80dda8f0bc))

#### Dependencies

- Update dependency github:yvgude/lean-ctx to v3.9.3 (#394) (mise) ([66c707b](https://github.com/y-miyazaki/config/commit/66c707b9bedc2346816504e9c336915d4474893d))
- Update aws-actions/configure-aws-credentials action to v6.2.2 (#386) (github-actions) ([a188072](https://github.com/y-miyazaki/config/commit/a188072d5758dcaa37954e1758bcefd614b798a4))
- Update actions/setup-java action to v5.5.0 (#391) (github-actions) ([d1bff9e](https://github.com/y-miyazaki/config/commit/d1bff9e11d0f452662a3fbf7c1ea917fd3db6c89))
- Update module go:golang.org/x/tools/gopls to v0.23.0 (#392) (mise) ([94e7f51](https://github.com/y-miyazaki/config/commit/94e7f513dea6ad5e7991290beaa1f30fc5683519))

## [1.8.24] - 2026-07-15

### Changed

- Align pins to v1.8.24 (b69a441) ([9cad779](https://github.com/y-miyazaki/config/commit/9cad7792fa027690541612ba5dd8e194e0832357))
- Finalize all pins v1.8.24 (ef50439) ([b69a441](https://github.com/y-miyazaki/config/commit/b69a441bbf15cf3d7a02f5fb7377f9ec81f14e45))
- Pin all to release v1.8.24 (eff5232) ([ef50439](https://github.com/y-miyazaki/config/commit/ef50439e351489dfb4503a47fb7cbef5a72e76d3))
- Pin all to v1.8.24 (266cff5) ([eff5232](https://github.com/y-miyazaki/config/commit/eff5232023d6139ae064aaff01d86680e5bc7b32))
- Enhance loop script with grouping for verifier attempts ([266cff5](https://github.com/y-miyazaki/config/commit/266cff567d0447cdf7f4024630518f6bc95d4089))
- Promote state for PR #393 [skip ci] (loop) ([f17a519](https://github.com/y-miyazaki/config/commit/f17a519ddcd90c8ab7ba2fedc39cced906dfd917))
- Loop-automated update (attempt 1) (#393) ([9ca7f08](https://github.com/y-miyazaki/config/commit/9ca7f086b4dccbf044e223b3da017e60157c77fc))
- Append run log [skip ci] (loop) ([2bd26c7](https://github.com/y-miyazaki/config/commit/2bd26c7a9789a5272d1a1d6b7691814c9cc5a6d1))
- Update state [skip ci] (loop) ([6a7eb99](https://github.com/y-miyazaki/config/commit/6a7eb998209b32d2ad8b23d10ce227c0d89c40ad))
- Update state [skip ci] (loop) ([95e824c](https://github.com/y-miyazaki/config/commit/95e824c382f2acbe12f48857cd0f670468667951))

## [1.8.23] - 2026-07-15

### Changed

- Align pins to v1.8.23 (8f636c5) ([c07d006](https://github.com/y-miyazaki/config/commit/c07d006edcf1860ce5ba85cbeb999bd319d40692))
- Finalize all pins v1.8.23 (e89bafc) ([8f636c5](https://github.com/y-miyazaki/config/commit/8f636c5439196590a9de61b5ec4710bcbdd7cca5))
- Pin all to release v1.8.23 (479d3b1) ([e89bafc](https://github.com/y-miyazaki/config/commit/e89bafc00a46b0a808394f11a87cad3f4b461363))
- Pin all to v1.8.23 (87aa50a) ([479d3b1](https://github.com/y-miyazaki/config/commit/479d3b1b9b4baf729186079c6a72b7fa32ed8df7))
- Update instruction and checklist files for improved clarity and precision ([87aa50a](https://github.com/y-miyazaki/config/commit/87aa50ae1b35e43948678f80bd5ba1c36e726594))

#### Dependencies

- Update dependency claude to v2.1.204 (#390) (mise) ([2ca60ea](https://github.com/y-miyazaki/config/commit/2ca60eaa2f7aa5605c7ddcd8351cf5ff8145d0e5))
- Update dependency aqua:github/copilot-cli to v1.0.69 (#389) (mise) ([1c4761c](https://github.com/y-miyazaki/config/commit/1c4761cb7bdcbb488c140a2685ee9ea232c3de1c))
- Update dependency aqua:aws/aws-cli to v2.35.17 (#388) (mise) ([40fca05](https://github.com/y-miyazaki/config/commit/40fca05edfde676028c9b48ad5ab8c071b048635))
- Update dependency aqua:astral-sh/uv to v0.11.28 (#387) (mise) ([9755d48](https://github.com/y-miyazaki/config/commit/9755d48990f5fd012fbd7ab77563bde1d5252015))
- Update dependency astral-sh/uv to v0.11.28 (#385) (github-actions-tool-version) ([1e9880c](https://github.com/y-miyazaki/config/commit/1e9880c352a66d903941900f864987ff6c1bd8a3))
- Update mise to v2026.7.2 (#384) (github-actions-tool-version) ([9cc74fd](https://github.com/y-miyazaki/config/commit/9cc74fdedc8ecd6057f5ba0c1a4bb3bb01d3d672))
- Update dependency golang/go to v1.26.5 (#383) (github-actions-tool-version) ([7de604c](https://github.com/y-miyazaki/config/commit/7de604c5a5ab05cb368bd47bdf60b6be266712e7))

## [1.8.22] - 2026-07-14

### Changed

- Align pins to v1.8.22 (4885292) ([3283b34](https://github.com/y-miyazaki/config/commit/3283b34bd5d549ecceaba0fbf0916e910f8f21c9))
- Finalize all pins v1.8.22 (a6478a1) ([4885292](https://github.com/y-miyazaki/config/commit/4885292fd83f1a0db7d8bbdee476486ee566d4b6))
- Pin all to release v1.8.22 (6f6613e) ([a6478a1](https://github.com/y-miyazaki/config/commit/a6478a1fc17618904de851702a499a78b0766fcb))
- Pin all to v1.8.22 (e64f1af) ([6f6613e](https://github.com/y-miyazaki/config/commit/6f6613ec09af4ba3744bb14ae809b3458ff325e0))
- Promote state for PR #381 [skip ci] (loop) ([dfe9268](https://github.com/y-miyazaki/config/commit/dfe9268a3a15aa7cb12848a1243c08949139fa38))
- Loop-automated update (attempt 1) (#381) ([a74ce08](https://github.com/y-miyazaki/config/commit/a74ce084cdc65c77d1a32e66a798b9d8da78cb18))
- Append run log [skip ci] (loop) ([8fe16af](https://github.com/y-miyazaki/config/commit/8fe16af124e2882c6495648b49fa12a7d409d38d))
- Update state [skip ci] (loop) ([4fd691d](https://github.com/y-miyazaki/config/commit/4fd691dd764159bc7aed9a4b623eec9962eeeb9c))
- Update state [skip ci] (loop) ([4303d0d](https://github.com/y-miyazaki/config/commit/4303d0d9f8ffe4085d9c01864bfd82203719e525))
- Promote state for PR #379 [skip ci] (loop) ([25424ea](https://github.com/y-miyazaki/config/commit/25424ea6d7c81da0de6bd8a2c13ef313404ada5f))
- Loop-automated update (attempt 1) (#379) ([9aec23b](https://github.com/y-miyazaki/config/commit/9aec23bc0b5f7a710d0ad486981faf7f84701ec6))
- Append run log [skip ci] (loop) ([40f32c6](https://github.com/y-miyazaki/config/commit/40f32c649277fd743e4ee6b59129811d448a95c4))
- Update state [skip ci] (loop) ([f5ccde7](https://github.com/y-miyazaki/config/commit/f5ccde7461a935822972d9701c0570062a3a5d68))
- Update state [skip ci] (loop) ([98c4627](https://github.com/y-miyazaki/config/commit/98c46277d918b1a0b2bae8b20f171e5fe3cd5a02))
- Update mcp configurations and dependencies to use lean-ctx-bin and new uvx version ([806c4d8](https://github.com/y-miyazaki/config/commit/806c4d8f46135e08c756fef9bc7dffc19874b3d7))

#### Dependencies

- Update ecspresso to v2.8.5 (#382) (ecspresso) ([e64f1af](https://github.com/y-miyazaki/config/commit/e64f1af97634cbf7a6f51a58997d1e115da8b8af))
- Update dependency github:yvgude/lean-ctx to v3.9.2 (#380) (mise) ([6d04020](https://github.com/y-miyazaki/config/commit/6d04020a928aa85ec6961c6a8bcf60e978eb05df))
- Update mise to v2026.7.1 (#378) (github-actions-tool-version) ([4ef0b9f](https://github.com/y-miyazaki/config/commit/4ef0b9fa0048aa828ddcb8afbe396595e68feb15))

## [1.8.21] - 2026-07-14

### Changed

- Align pins to v1.8.21 (98020d8) ([d4b44ec](https://github.com/y-miyazaki/config/commit/d4b44ecf01aa52a08aed550da99a735009af531b))
- Finalize all pins v1.8.21 (2361d1b) ([98020d8](https://github.com/y-miyazaki/config/commit/98020d80e7a86fa253748b23b19443ff57f97e1b))
- Pin all to release v1.8.21 (34074c9) ([2361d1b](https://github.com/y-miyazaki/config/commit/2361d1b8a03c043bb568581362af340e82c7d363))
- Pin all to v1.8.21 (77ca5b0) ([34074c9](https://github.com/y-miyazaki/config/commit/34074c97d7efc2db36a63dc9887d24a3b02b9b38))
- Update exclude patterns in pre-commit configuration files to include .loop/ state ([4a83ca3](https://github.com/y-miyazaki/config/commit/4a83ca30097c12fff60f04f61b76d72b13070c89))
- Update last_sha in state-changelog.json (loop) ([a1f76b3](https://github.com/y-miyazaki/config/commit/a1f76b3100ada8fbdff495c3bf5814663d92c018))

#### Dependencies

- Update module go:github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen to v2.7.2 (#377) (mise) ([77ca5b0](https://github.com/y-miyazaki/config/commit/77ca5b091c315c3a8177ab802511b038abf52c97))
- Update dependency claude to v2.1.202 (#376) (mise) ([1c8daad](https://github.com/y-miyazaki/config/commit/1c8daad582ad7d9d2935d0de336365ae5e44a8ca))
- Update dependency aqua:astral-sh/uv to v0.11.27 (#375) (mise) ([6b83afa](https://github.com/y-miyazaki/config/commit/6b83afa570961f5ef4f8b2d86b122fb44a00f833))
- Update dependency aqua:jdx/usage to v3.5.4 (#374) (mise) ([4f31067](https://github.com/y-miyazaki/config/commit/4f31067ef4701f155df1501725bb3aba1a3da0d3))
- Update dependency aqua:aws/aws-cli to v2.35.16 (#373) (mise) ([429d910](https://github.com/y-miyazaki/config/commit/429d910e0e0c28596e3ccf75b857f3836c96af14))
- Update dependency github:yvgude/lean-ctx to v3.9.1 (#355) (mise) ([c3a1a79](https://github.com/y-miyazaki/config/commit/c3a1a790b4492dfe9f9b24e2eb0e138014ef484f))

## [1.8.20] - 2026-07-13

### Added

- Add run_agent_capture function to preserve USAGE_* globals and update agent calls (loop) ([02fb2c7](https://github.com/y-miyazaki/config/commit/02fb2c73f242d1544de2ae0561b25b37de9787c3))

### Changed

- Align pins to v1.8.20 (fd6e4af) ([18bb7a9](https://github.com/y-miyazaki/config/commit/18bb7a935d5c91d056fba9120e513d90b8c968c9))
- Finalize all pins v1.8.20 (c4ca066) ([fd6e4af](https://github.com/y-miyazaki/config/commit/fd6e4af7771901f16cd1780fa777f9f2c7539753))
- Pin all to release v1.8.20 (ffc0f95) ([c4ca066](https://github.com/y-miyazaki/config/commit/c4ca0661925756794dfe888a4c91f6c880558f3e))
- Pin all to v1.8.20 (02fb2c7) ([ffc0f95](https://github.com/y-miyazaki/config/commit/ffc0f9575b6d3d4f0dc9aab40e498b862205f455))
- Promote state for PR #372 [skip ci] (loop) ([8b8e065](https://github.com/y-miyazaki/config/commit/8b8e065e3ecbdd41084f3b254e46c08c5858f12d))
- Loop-automated update (attempt 1) (#372) ([efecc24](https://github.com/y-miyazaki/config/commit/efecc2477026b50c116492a1aaf135c49e832958))
- Append run log [skip ci] (loop) ([77830d8](https://github.com/y-miyazaki/config/commit/77830d81009ca3536cc909fec05ded1c338f5f94))
- Update state [skip ci] (loop) ([1b23f8c](https://github.com/y-miyazaki/config/commit/1b23f8cd8eba3aa7098e67b30516bb3cd8004e35))
- Update state [skip ci] (loop) ([f1c7ee7](https://github.com/y-miyazaki/config/commit/f1c7ee731f0b5ae491fc68532f446d20841829ed))
- Raise changelog daily run budget for verification (loop) ([c88ec17](https://github.com/y-miyazaki/config/commit/c88ec170e8073ec9aea283a811cec84f0ec3f183))
- Append run log [skip ci] (loop) ([c71f337](https://github.com/y-miyazaki/config/commit/c71f3371e1494329468f35aecb5b1ffa442cbf5a))
- Append run log [skip ci] (loop) ([2b5f4d2](https://github.com/y-miyazaki/config/commit/2b5f4d2815ee8302972d74d4c3d8680d9e61fd42))
- Append run log [skip ci] (loop) ([86e1474](https://github.com/y-miyazaki/config/commit/86e1474190376631e03a924d23b009eb4d26d12b))
- Update state [skip ci] (loop) ([4a7e61c](https://github.com/y-miyazaki/config/commit/4a7e61cc67e3f9d2ee610f12981421fa01797a56))
- Update state [skip ci] (loop) ([9bd18ea](https://github.com/y-miyazaki/config/commit/9bd18ea0a586e644171111e716c24cef39b5aa1a))
- Append run log [skip ci] (loop) ([cdee5e1](https://github.com/y-miyazaki/config/commit/cdee5e15b689520b10d49f9bb1785ec5d3bd0f1d))
- Update state [skip ci] (loop) ([3603856](https://github.com/y-miyazaki/config/commit/3603856051ac0080c3ee80125d514baf887ac020))
- Update state [skip ci] (loop) ([6cf2905](https://github.com/y-miyazaki/config/commit/6cf29050513796511faf40cc1b664ec6f083bc09))

## [1.8.19] - 2026-07-13

### Changed

- Align pins to v1.8.19 (dba789f) ([134c3b0](https://github.com/y-miyazaki/config/commit/134c3b03d624a0d4884c8285197427e7f4e07cd9))
- Finalize all pins v1.8.19 (4828344) ([dba789f](https://github.com/y-miyazaki/config/commit/dba789ff1d2fe4146e28b9128d61476c9c5576bd))
- Pin all to release v1.8.19 (aa83d9a) ([4828344](https://github.com/y-miyazaki/config/commit/4828344317149e19cb697d7dcb2a0cf1044cb167))
- Pin all to v1.8.19 (5cba13b) ([aa83d9a](https://github.com/y-miyazaki/config/commit/aa83d9a4ded0c972ee833e2cadb59857f0b1ed32))
- Update workflows to utilize explicit secrets mapping for maintenance bot ([5cba13b](https://github.com/y-miyazaki/config/commit/5cba13bb0996626a60e22421815205ace55ab8bd))

## [1.8.18] - 2026-07-13

### Changed

- Align pins to v1.8.18 (a4f597f) ([a3c85ba](https://github.com/y-miyazaki/config/commit/a3c85ba40048840ae454b720c4f845b45fae7b09))
- Finalize all pins v1.8.18 (4d93be4) ([a4f597f](https://github.com/y-miyazaki/config/commit/a4f597fa5f88923d8d0d012d356d5bc11409265f))
- Pin all to release v1.8.18 (873701a) ([4d93be4](https://github.com/y-miyazaki/config/commit/4d93be4adee01e60c48fb3deaee0ab7930e22fa6))
- Pin all to v1.8.18 (bcdeced) ([873701a](https://github.com/y-miyazaki/config/commit/873701ac06836bd2a8813e55edc44f29526ac41f))
- Add maintenance bot token generation and update workflows to use it ([bcdeced](https://github.com/y-miyazaki/config/commit/bcdeced6e62a31dbb5cc56043f874ab2873a9be7))

## [1.8.17] - 2026-07-13

### Changed

- Align pins to v1.8.17 (6f1947b) ([a8c7575](https://github.com/y-miyazaki/config/commit/a8c75754f830ffd4aa201a1cf1340ede8296cf8a))
- Finalize all pins v1.8.17 (0ed0898) ([6f1947b](https://github.com/y-miyazaki/config/commit/6f1947b75d02265f87cd97888193497add65ac7f))
- Pin all to release v1.8.17 (5d8dbb5) ([0ed0898](https://github.com/y-miyazaki/config/commit/0ed08987892ba7b169a46a4c4d58aafba0d52256))
- Pin all to v1.8.17 (fe30066) ([5d8dbb5](https://github.com/y-miyazaki/config/commit/5d8dbb56cea54537561e86da81184201fabe5a56))
- Finalize all pins v1.8.17 (fe15f0d) ([fe30066](https://github.com/y-miyazaki/config/commit/fe3006679ab2f80c530619894ee48b1e858d3e15))
- Pin all to release v1.8.17 (e40edea) ([442eac5](https://github.com/y-miyazaki/config/commit/442eac5028e7e229166d23078d22e054c61af52f))
- Pin all to v1.8.17 (85cdd84) ([4534eac](https://github.com/y-miyazaki/config/commit/4534eac4f96d3bd2efdce2ab033b297e58421ff7))
- Loop-automated update (attempt 1) (#366) ([f74661d](https://github.com/y-miyazaki/config/commit/f74661d956029e91ee7e346e30f384160762df75))
- Update loop-changelog to support undocumented releases ([85cdd84](https://github.com/y-miyazaki/config/commit/85cdd8420d16e571381c9add44e005d230a7d5a4))

## [1.8.16] - 2026-07-13

### Added

- Enhance failure detection and logging for startup failures (loop-ci-sweeper) ([4ec2afa](https://github.com/y-miyazaki/config/commit/4ec2afac47573cef117edf82166360498647299e))

### Changed

- Align pins to v1.8.16 (79d74d1) ([732e63a](https://github.com/y-miyazaki/config/commit/732e63a2937d807787b5316c684650b7667080db))
- Finalize all pins v1.8.16 (8171ef0) ([79d74d1](https://github.com/y-miyazaki/config/commit/79d74d1dadea776a3a99178c3e082e7fe5d7db65))
- Pin all to release v1.8.16 (5159954) ([8171ef0](https://github.com/y-miyazaki/config/commit/8171ef0fb582e1d650e87c3851c7d4136901740f))
- Pin all to v1.8.16 (4ec2afa) ([5159954](https://github.com/y-miyazaki/config/commit/515995443de1a545b589b5cc88b03b6e9006d845))

## [1.8.15] - 2026-07-13

### Fixed

- Restore workflow pins broken in finalize commit ([43fadab](https://github.com/y-miyazaki/config/commit/43fadab51578769b295a0a2a2a64ccd56941bbbf))

### Changed

- Align pins to v1.8.15 (905185e) ([78a7272](https://github.com/y-miyazaki/config/commit/78a7272b209511b559d75f5ef45e6f564c9b16a5))
- Finalize all pins v1.8.15 (b6b0f25) ([905185e](https://github.com/y-miyazaki/config/commit/905185e56867e4ba406ba7d77d34395ac969530e))
- Pin all to release v1.8.15 (96eb1d0) ([b6b0f25](https://github.com/y-miyazaki/config/commit/b6b0f2535131f1b189af9ca5f8abca81c476d372))
- Pin all to v1.8.15 (9cd7438) ([96eb1d0](https://github.com/y-miyazaki/config/commit/96eb1d0a2491e233fce6abb039c43ea4a46897c1))
- Remove nested composite actions and add lib tests (loop) ([9cd7438](https://github.com/y-miyazaki/config/commit/9cd74389135a1a4888f68a896ec9aed347bda3df))
- Sync workflow pins to release SHA e9584c0 ([703a60d](https://github.com/y-miyazaki/config/commit/703a60d6b2bf3f627ec52fbbd51de097a36abd8c))

#### Dependencies

- Update y-miyazaki/config digest to f4d9a47 (#357) (github-actions) ([0705e5c](https://github.com/y-miyazaki/config/commit/0705e5c607de110bc56e1bd08e196c045dc3621b))

## [1.8.14] - 2026-07-13

### Changed

- Finalize workflow pins v1.8.14 (c36da55) ([27acb41](https://github.com/y-miyazaki/config/commit/27acb41d6df94e81b05adce9a30d00241680dec9))
- Pin workflows to release v1.8.14 (6c2e00a) ([c36da55](https://github.com/y-miyazaki/config/commit/c36da5529289217d73a2c98d1493b688400a2a7c))
- Pin workflows to v1.8.14 (703a60d) ([6c2e00a](https://github.com/y-miyazaki/config/commit/6c2e00ac48b6424902da6f5eb0b5cb9795f94ed7))
- Finalize workflow pins for v1.8.14 (b338036) ([e9584c0](https://github.com/y-miyazaki/config/commit/e9584c0415c85cfb351b49cc13d5b88dc729768d))
- Pin workflows to v1.8.14 release (b255049) ([b338036](https://github.com/y-miyazaki/config/commit/b3380368e9a5ecabf60601d1feedf81031c387c1))
- Pin workflows to v1.8.14 (43fadab) ([b255049](https://github.com/y-miyazaki/config/commit/b25504956ed42e022112d6fa215efd4052902abe))
- Finalize workflow pins for v1.8.14 ([c3779fb](https://github.com/y-miyazaki/config/commit/c3779fb333745428fce5b749ca4b50a424154e22))
- Pin workflows to v1.8.14 release (22ac86b) ([f4d9a47](https://github.com/y-miyazaki/config/commit/f4d9a47e5dd291ae096004eeb77efc84cd3f7a17))
- Pin action internals to v1.8.14 tag ref ([22ac86b](https://github.com/y-miyazaki/config/commit/22ac86bfbe8f805f3a4277fe73c0bdfbd875af68))
- Pin workflows to v1.8.14 (2051327) ([ea3f5d0](https://github.com/y-miyazaki/config/commit/ea3f5d033aeaf6bdfeb2ab2ef8ffe4da9be6ff27))
- Pin config actions to v1.8.14 (pass 2) ([2051327](https://github.com/y-miyazaki/config/commit/205132765340fd775496c067a3841a6791455248))
- Pin config actions to v1.8.14 (pass 1) ([3b6cde7](https://github.com/y-miyazaki/config/commit/3b6cde76d477e0878c6c4bf84f47a6d63eb9e6f5))
- Enhance loop detection script with JSON handling functions ([ea3d28e](https://github.com/y-miyazaki/config/commit/ea3d28e1abe411e21443eba7f57c7d5cdab585f9))
- Update GitHub Actions to use version 1.8.13 for loop actions ([14c1564](https://github.com/y-miyazaki/config/commit/14c15649f9ad935ed18adf377fecaad4e7e15ae4))

## [1.8.13] - 2026-07-13

### Changed

- Update GitHub Actions to use version 1.8.12 for loop actions ([138fed8](https://github.com/y-miyazaki/config/commit/138fed890fd0a20e0ac1cfceb8d2c1752d177cce))

## [1.8.12] - 2026-07-13

### Changed

- Enhance JSON escaping function across multiple scripts ([ac1e7be](https://github.com/y-miyazaki/config/commit/ac1e7be20e48cdff0216362ecfca66e8459bceb6))
- Update documentation and references in AWS service comparison reports ([7c72d01](https://github.com/y-miyazaki/config/commit/7c72d017b76f50719135801f190964eb4010b2e4))
- Update GitHub Actions to use version 1.8.11 for loop actions ([576036c](https://github.com/y-miyazaki/config/commit/576036c0c9779b4c775003994fcd11c743af85f9))

## [1.8.11] - 2026-07-13

### Changed

- Update GitHub Actions to use version 1.8.10 for loop actions ([80b985d](https://github.com/y-miyazaki/config/commit/80b985dd67f10ac3604817999902c893fba578db))

## [1.8.10] - 2026-07-13

### Changed

- Update checklist documentation and generated files ([2764111](https://github.com/y-miyazaki/config/commit/276411164d29b6f174f4e64b6b25ea5fb2cc73a4))

## [1.8.9] - 2026-07-12

### Changed

- Update GitHub Actions to use version 1.8.8 for loop actions ([5a54080](https://github.com/y-miyazaki/config/commit/5a5408053a1d6bf357808590ae74f5ccb8eb31f4))
- Update GitHub Actions to use loop-install-cli and other actions version 1.8.8 ([0f703f2](https://github.com/y-miyazaki/config/commit/0f703f2b8c74ec8ce7bfa017431e69739c0cc7b6))

## [1.8.8] - 2026-07-12

### Fixed

- Change file permissions for update_run_ledger.sh and update devcontainer.json ([6aa8c76](https://github.com/y-miyazaki/config/commit/6aa8c76c4f1a720cd9b5d2ed25b234c4c095ac38))

### Changed

- Enhance loop workflows and documentation ([f8209c2](https://github.com/y-miyazaki/config/commit/f8209c294e79f51f618531ced4022e5a50c239a9))
- Enhance loop workflows and documentation ([8b68659](https://github.com/y-miyazaki/config/commit/8b686591fdbc2e3e670c8e6c5d2d9e431ed3380f))
- Update loop-changelog skill and related scripts ([f9396d5](https://github.com/y-miyazaki/config/commit/f9396d59b113cb8dd0dda1ceebc266a7a086e9d7))
- Update tool comparison matrix for AI agent hooks ([3c534a2](https://github.com/y-miyazaki/config/commit/3c534a2b6ee594a08eb6cce6ff02b391a42282f7))
- Update GitHub Actions to use loop-install-cli and other actions version 1.8.7 ([0247a76](https://github.com/y-miyazaki/config/commit/0247a7601c6f8efefb568c802efa8ca7bcdf959b))

#### Dependencies

- Lock file maintenance (#354) (mise) ([75a7436](https://github.com/y-miyazaki/config/commit/75a743620abf3bcc1ec3fae34f3d82c035024beb))

## [1.8.7] - 2026-07-12

### Changed

- Update GitHub Actions to use loop-install-cli and other actions version 1.8.6 ([7600459](https://github.com/y-miyazaki/config/commit/7600459ef9155b734fb641e68bc556f097bcfaeb))

## [1.8.6] - 2026-07-12

### Changed

- Enhance tool comparison matrix for AI agent hooks ([841a196](https://github.com/y-miyazaki/config/commit/841a1962c1ecbd79867cccc2cbf22a6c201afccf))
- Add loop-changelog skill and update related configurations ([d9a6a9b](https://github.com/y-miyazaki/config/commit/d9a6a9b51af78c6879a21baf4dc2b33d939a5407))
- Update documentation and scripts for loop-docs-triage skill ([edba084](https://github.com/y-miyazaki/config/commit/edba0848bb34ff183d759230e091a397168c86f6))
- Loop-automated update (attempt 1) (#350) ([e9c068e](https://github.com/y-miyazaki/config/commit/e9c068e8988a4a0405bcddfc47a0b8907e93fad6))

#### Dependencies

- Update dependency github:microsoft/apm to v0.24.0 (#353) (mise) ([fe7a10f](https://github.com/y-miyazaki/config/commit/fe7a10f4ef6f49a1a9722474f0f2653d4b3e585d))
- Update dependency pnpm to v11.10.0 (#313) (mise) ([4238e81](https://github.com/y-miyazaki/config/commit/4238e8154e6b6e50afd34c2b0ccdfbb28245d146))
- Update goreleaser to v2.17.0 (#352) (goreleaser) ([b4a0f6b](https://github.com/y-miyazaki/config/commit/b4a0f6b43587ba6c14e9ebb17e6a5db77220642a))

## [1.8.5] - 2026-07-11

### Changed

- Update GitHub Actions to use loop-install-cli and other actions version 1.8.4 ([2c56aa0](https://github.com/y-miyazaki/config/commit/2c56aa01ad05ff9a45d6dd0dfb3f65b39a03766c))

[1.8.58]: https://github.com/y-miyazaki/config/compare/v1.8.57...00d6e7a9346341b5fc6318893ff71b80b670fd62
[1.8.57]: https://github.com/y-miyazaki/config/compare/v1.8.56...71c34979da6e9fc36c18431859f68c2680a5bb9f
[1.8.56]: https://github.com/y-miyazaki/config/compare/v1.8.55...01a42fc43c278cf8a38616de8de24fe7b6285f04
[1.8.55]: https://github.com/y-miyazaki/config/compare/v1.8.54...5a725c44406bb5a7d7e32cdc69ddf3fe20d4afd3
[1.8.54]: https://github.com/y-miyazaki/config/compare/v1.8.53...59dd8fabd9d9396711cb913ccc707da47634d164
[1.8.53]: https://github.com/y-miyazaki/config/compare/v1.8.52...a593e0f8e283e5595f1d31675a3a117bca713706
[1.8.52]: https://github.com/y-miyazaki/config/compare/v1.8.51...1d689aa8bf3617c8927c76db3f2ec79f874d7986
[1.8.51]: https://github.com/y-miyazaki/config/compare/v1.8.50...e6c9d54dd8acbc9f72e2ae78c735414e420aee50
[1.8.50]: https://github.com/y-miyazaki/config/compare/v1.8.49...1bdad6bbbe6c0acd740551a08a05e7eb3231a9a8
[1.8.49]: https://github.com/y-miyazaki/config/compare/v1.8.48...b7dbe0b8b43ebe4e476c2466c858fefd9b7728d9
[1.8.48]: https://github.com/y-miyazaki/config/compare/v1.8.47...af5d2849a2897c2bbfd13e54afb010a865c95b39
[1.8.47]: https://github.com/y-miyazaki/config/compare/v1.8.46...0563091c60057dabde8167fbb6e00bf3453639fc
[1.8.46]: https://github.com/y-miyazaki/config/compare/v1.8.45...7466dbe9ec68181e11c785572180b940b1e56b3c
[1.8.45]: https://github.com/y-miyazaki/config/compare/v1.8.44...580c092e719ab1d45b9fa7f19fda2ea6bef69d8f
[1.8.44]: https://github.com/y-miyazaki/config/compare/v1.8.43...c1fa67315e4c3b77c23526d019c5375ee151aeda
[1.8.43]: https://github.com/y-miyazaki/config/compare/v1.8.42...803cb1805788ec38018a16c44c26e2b01f6b95ef
[1.8.42]: https://github.com/y-miyazaki/config/compare/v1.8.41...4a0df8bd929df6eeddc8f1286bdda0ad129d11d7
[1.8.41]: https://github.com/y-miyazaki/config/compare/v1.8.40...14ad6edf009a0a68817066c32fd7f95e79616ccf
[1.8.40]: https://github.com/y-miyazaki/config/compare/v1.8.39...2c8c9ce50a31e97aeec3f32b06763bc1e2b23637
[1.8.39]: https://github.com/y-miyazaki/config/compare/v1.8.38...9ba61b96a0ba594c92eb957fed74482547a96fe7
[1.8.38]: https://github.com/y-miyazaki/config/compare/v1.8.37...7e0adb3e57ad6674028134e05e8cf33aef4e4fd5
[1.8.37]: https://github.com/y-miyazaki/config/compare/v1.8.36...1f0b8eb1e74a8e0b12bb6c2cfc71b92071084e48
[1.8.36]: https://github.com/y-miyazaki/config/compare/v1.8.35...e9f7e78c864e2bcdc0ed724ea718573f9ff4df55
[1.8.35]: https://github.com/y-miyazaki/config/compare/v1.8.34...3373cba072024c0883ccc3ebe38da46c481118f2
[1.8.34]: https://github.com/y-miyazaki/config/compare/v1.8.33...938701916a57f5f1f482bc2ddab9da3b2e5e91b3
[1.8.33]: https://github.com/y-miyazaki/config/compare/v1.8.32...c2e43ed67ab1e08878771acc267841f12e9f601f
[1.8.32]: https://github.com/y-miyazaki/config/compare/v1.8.31...7a51271120c6ab965a606d86d3cc4dbad8922477
[1.8.31]: https://github.com/y-miyazaki/config/compare/v1.8.30...73d74ce12720bcad2e95b56c30cf475d2a7e751a
[1.8.30]: https://github.com/y-miyazaki/config/compare/v1.8.29...0098282039f73bf3aba3a67a02568c0dec11c2a5
[1.8.29]: https://github.com/y-miyazaki/config/compare/v1.8.28...45afa9c0f1dd5b8227bfd9efc86345fd45b0e65c
[1.8.28]: https://github.com/y-miyazaki/config/compare/v1.8.27...7b0e8557d0544acef512cb7e5e81f96abf19bd44
[1.8.27]: https://github.com/y-miyazaki/config/compare/v1.8.26...918db24bc160b02462748456a742eba08c78cbf0
[1.8.26]: https://github.com/y-miyazaki/config/compare/v1.8.25...f2c4021e7dbe45f824eaf46d86641a3ff6624979
[1.8.25]: https://github.com/y-miyazaki/config/compare/v1.8.24...175b15b5ccc689524c9370247597666446007cc8
[1.8.24]: https://github.com/y-miyazaki/config/compare/v1.8.23...b69a441bbf15cf3d7a02f5fb7377f9ec81f14e45
[1.8.23]: https://github.com/y-miyazaki/config/compare/v1.8.22...8f636c5439196590a9de61b5ec4710bcbdd7cca5
[1.8.22]: https://github.com/y-miyazaki/config/compare/v1.8.21...4885292fd83f1a0db7d8bbdee476486ee566d4b6
[1.8.21]: https://github.com/y-miyazaki/config/compare/v1.8.20...98020d80e7a86fa253748b23b19443ff57f97e1b
[1.8.20]: https://github.com/y-miyazaki/config/compare/v1.8.19...fd6e4af7771901f16cd1780fa777f9f2c7539753
[1.8.19]: https://github.com/y-miyazaki/config/compare/v1.8.18...dba789ff1d2fe4146e28b9128d61476c9c5576bd
[1.8.18]: https://github.com/y-miyazaki/config/compare/v1.8.17...a4f597fa5f88923d8d0d012d356d5bc11409265f
[1.8.17]: https://github.com/y-miyazaki/config/compare/v1.8.16...6f1947b75d02265f87cd97888193497add65ac7f
[1.8.16]: https://github.com/y-miyazaki/config/compare/v1.8.15...79d74d1dadea776a3a99178c3e082e7fe5d7db65
[1.8.15]: https://github.com/y-miyazaki/config/compare/v1.8.14...905185e56867e4ba406ba7d77d34395ac969530e
[1.8.14]: https://github.com/y-miyazaki/config/compare/v1.8.13...f4d9a47e5dd291ae096004eeb77efc84cd3f7a17
[1.8.13]: https://github.com/y-miyazaki/config/compare/v1.8.12...138fed890fd0a20e0ac1cfceb8d2c1752d177cce
[1.8.12]: https://github.com/y-miyazaki/config/compare/v1.8.11...ac1e7be20e48cdff0216362ecfca66e8459bceb6
[1.8.11]: https://github.com/y-miyazaki/config/compare/v1.8.10...80b985dd67f10ac3604817999902c893fba578db
[1.8.10]: https://github.com/y-miyazaki/config/compare/v1.8.9...276411164d29b6f174f4e64b6b25ea5fb2cc73a4
[1.8.9]: https://github.com/y-miyazaki/config/compare/v1.8.8...5a5408053a1d6bf357808590ae74f5ccb8eb31f4
[1.8.8]: https://github.com/y-miyazaki/config/compare/v1.8.7...f8209c294e79f51f618531ced4022e5a50c239a9
[1.8.7]: https://github.com/y-miyazaki/config/compare/v1.8.6...7600459ef9155b734fb641e68bc556f097bcfaeb
[1.8.6]: https://github.com/y-miyazaki/config/compare/v1.8.5...fe7a10f4ef6f49a1a9722474f0f2653d4b3e585d
[1.8.5]: https://github.com/y-miyazaki/config/compare/v1.8.4...v1.8.5
