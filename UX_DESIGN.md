# UI/UX design decisions

The app uses these principles as design guidance, not a claim of universal compliance. Real usability, accessibility, and device testing remain necessary.

| Principle | Applied behavior |
| --- | --- |
| Familiar conventions (Jakob) | Stable Home, Repairs, Appointments, Profile navigation; recognizable back, search, date picker, form, and status patterns. |
| Choice complexity (Hick) | One prominent primary action per task, a compact time selector, and secondary account actions separated from active work. |
| Reachable controls (Fitts) | Shared buttons, icon buttons, and tappable cards have at least 48 logical pixels of touch area. Focusable Material controls replace text-only gesture links. |
| Memory and recognition (Miller) | Contact, address, repair, schedule, and review information is grouped into meaningful sections. No arbitrary seven-item cap. Entered information remains visible or available while editing. |
| Proximity and hierarchy | A 4/8-point spacing rhythm; related information stays within a card. Titles, main text, and supporting text have distinct roles. Appointments and repair status appear before account shortcuts. |
| Complexity ownership (Tesler) | Saved details are reused; the app can suggest an address from phone location. Users can correct the suggestion or enter it manually. Business requirements remain explicit. |
| Feedback and responsiveness (Doherty / Nielsen) | Busy actions acknowledge input immediately and prevent duplicate requests. Data remains visible during refresh. Skeletons name the pending content and explain longer waits without inventing completion percentages. Read failures offer recovery. |
| Accessibility and control | Required fields have text errors; important invalid fields are brought into view. Status uses words as well as color. Layouts support larger text; motion-sensitive users receive static placeholders. Permission denial never blocks manual address entry. |
| Visual consistency | Locally bundled Roboto for all UI text, one Material outline icon family, semantic theme colors, consistent card shape and spacing. No emoji-based controls. |

## Type and spacing

- Main headings: 28 px; screen titles: 22 px; section headings: 18 px.
- Form/body/action text: 16 px; supporting text: 14 px; small metadata: 12 px.
- Use weight and spacing for emphasis. Do not introduce extra font families or decorative icon styles.
- Use 8–12 px within related groups, 16 px card padding, and 24–32 px between sections. Constrain wide layouts rather than stretching forms across a desktop viewport.

## Loading and address requirements

Use loading feedback to communicate real work. Animation does not make a request faster and no artificial delay is added. Respect reduced-motion settings. When a request fails, distinguish that failure from a successful empty result.

An address is required to register, save a profile, and book. Phone location is requested only after the user taps the location action. A detected address must be applied explicitly and remains editable. Keep manual entry available for denied permission, disabled GPS, unavailable geocoding, and unsupported platforms. Existing accounts without an address must add one before booking.

## References

- [Hick's Law](https://lawsofux.com/hicks-law/) and [Miller's Law](https://lawsofux.com/millers-law/): simplify decisions and organize related information without arbitrary numerical limits.
- [Doherty Threshold](https://lawsofux.com/doherty-threshold/): timely system feedback.
- [Nielsen Norman Group: progress indicators](https://www.nngroup.com/articles/progress-indicators/): explain waits and maintain visible system status.
- [WCAG 2.2](https://www.w3.org/TR/WCAG22/): contrast, keyboard access, visible focus, text resizing, and target accessibility. The app's 48-pixel control target is a design choice, not a claim that WCAG requires that exact value.

## Validation

- `dart analyze`: no issues.
- 95 automated app tests passed, covering required addresses, location permission and timeout recovery, data persistence, booking, form focus, retry behavior, and responsive layouts. The additional preview rendering check also passed.
- Screens were checked at narrow phone widths with enlarged text; both light and dark dashboard previews use the bundled Roboto font.
- Android debug APK built successfully. Live GPS, native permission dialogs, and iOS compilation still require testing on their respective devices/platforms.
