import 'session_archive_store.dart';
import 'session_notes_store.dart';
import 'session_pins_store.dart';
import 'session_recents_store.dart';

/// Facade over device-local session metadata stores.
/// Keeps existing key formats for backward compatibility.
class SessionLocalStore {
  SessionLocalStore({
    SessionPinsStore? pins,
    SessionNotesStore? notes,
    SessionArchiveStore? archive,
    SessionRecentsStore? recents,
  })  : _pins = pins ?? SessionPinsStore(),
        _notes = notes ?? SessionNotesStore(),
        _archive = archive ?? SessionArchiveStore(),
        _recents = recents ?? SessionRecentsStore();

  final SessionPinsStore _pins;
  final SessionNotesStore _notes;
  final SessionArchiveStore _archive;
  final SessionRecentsStore _recents;

  Future<({
    Set<String> pins,
    Set<String> archived,
    Map<String, String> notes,
    Map<String, int> recentRanks,
  })> loadAll() async {
    final pins = await _pins.pins();
    final archived = await _archive.archived();
    final notes = await _notes.all();
    final ranks = await _recents.ranks();
    return (
      pins: pins,
      archived: archived,
      notes: notes,
      recentRanks: ranks,
    );
  }

  Future<void> togglePin(String sessionKey) => _pins.toggle(sessionKey);

  Future<void> setPinned(String sessionKey, bool pinned) =>
      _pins.setPinned(sessionKey, pinned);

  Future<void> toggleArchive(String sessionKey) => _archive.toggle(sessionKey);

  Future<void> setArchived(String sessionKey, bool value) =>
      _archive.setArchived(sessionKey, value);

  Future<void> setNote(String sessionKey, String note) =>
      _notes.set(sessionKey, note);

  Future<String?> noteOf(String sessionKey) => _notes.get(sessionKey);

  Future<void> touchRecent(String sessionKey) => _recents.touch(sessionKey);

  Future<void> clearRecents() => _recents.clear();
}
