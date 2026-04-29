# Plan A + B Checklist

## Plan A: Architecture Refactor (behavior-preserving)
- [x] Extract design tokens module
- [x] Extract app theme module
- [x] Extract shared app state module
- [x] Rewire app root to use modules
- [ ] Split remaining feature screens into dedicated files (next pass)

## Plan B: Design System Hardening
- [x] Centralized palette constants
- [x] Centralized spacing/radius constants
- [x] Centralized motion constants
- [x] Theme typography aligned to design philosophy
- [ ] Build dedicated reusable primitive widgets package (next pass)

## Validation
- [ ] flutter analyze
- [ ] flutter test
- [ ] flutter build web --release
- [ ] flutter build apk --debug
