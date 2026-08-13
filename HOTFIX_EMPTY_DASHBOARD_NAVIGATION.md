# Empty dashboard / navigation hotfix

- Restored the last known-working `ManagementShell` implementation from the user's uploaded source ZIP.
- Removed the local Theme wrapper regression that was introduced in the approved UI package.
- Dashboard now renders its layout immediately instead of replacing the whole content area with a waiting widget.
- Dashboard workspace and personnel-performance requests are isolated and time-limited; one failed or hanging request can no longer blank the whole dashboard.
- Approved white UI and the other approved screen changes remain in place.
