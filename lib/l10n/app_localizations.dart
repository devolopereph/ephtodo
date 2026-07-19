import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_tr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('tr'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'ephtodo'**
  String get appTitle;

  /// No description provided for @startupFailed.
  ///
  /// In en, this message translates to:
  /// **'ephtodo could not start safely.'**
  String get startupFailed;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @finish.
  ///
  /// In en, this message translates to:
  /// **'Open workspace'**
  String get finish;

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'A calm place for what matters'**
  String get welcomeTitle;

  /// No description provided for @vaultTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your portable vault'**
  String get vaultTitle;

  /// No description provided for @completionTitle.
  ///
  /// In en, this message translates to:
  /// **'After completing a task'**
  String get completionTitle;

  /// No description provided for @trashTitle.
  ///
  /// In en, this message translates to:
  /// **'Trash retention'**
  String get trashTitle;

  /// No description provided for @themeTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your workspace theme'**
  String get themeTitle;

  /// No description provided for @syncTitle.
  ///
  /// In en, this message translates to:
  /// **'Local-network sync'**
  String get syncTitle;

  /// No description provided for @shortcutsTitle.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts and sticky window'**
  String get shortcutsTitle;

  /// No description provided for @finishTitle.
  ///
  /// In en, this message translates to:
  /// **'Foundation ready'**
  String get finishTitle;

  /// No description provided for @syncUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Sync is disabled in Phase 1.'**
  String get syncUnavailable;

  /// No description provided for @workspacePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Your workspace foundation is ready.'**
  String get workspacePlaceholder;

  /// No description provided for @showSticky.
  ///
  /// In en, this message translates to:
  /// **'Show sticky window'**
  String get showSticky;

  /// No description provided for @hideSticky.
  ///
  /// In en, this message translates to:
  /// **'Hide sticky window'**
  String get hideSticky;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @upcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get upcoming;

  /// No description provided for @projects.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get projects;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @archive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archive;

  /// No description provided for @trash.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get trash;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search tasks, projects, and tags'**
  String get search;

  /// No description provided for @quickAdd.
  ///
  /// In en, this message translates to:
  /// **'Quick add'**
  String get quickAdd;

  /// No description provided for @taskTitle.
  ///
  /// In en, this message translates to:
  /// **'Task title'**
  String get taskTitle;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @priority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get priority;

  /// No description provided for @startDate.
  ///
  /// In en, this message translates to:
  /// **'Start date (YYYY-MM-DD)'**
  String get startDate;

  /// No description provided for @dueDate.
  ///
  /// In en, this message translates to:
  /// **'Due date (YYYY-MM-DD)'**
  String get dueDate;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @deletePermanently.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get deletePermanently;

  /// No description provided for @emptyTrash.
  ///
  /// In en, this message translates to:
  /// **'Empty Trash'**
  String get emptyTrash;

  /// No description provided for @confirmEmptyTrash.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete everything in Trash?'**
  String get confirmEmptyTrash;

  /// No description provided for @nothingToday.
  ///
  /// In en, this message translates to:
  /// **'Nothing scheduled for today.'**
  String get nothingToday;

  /// No description provided for @nothingUpcoming.
  ///
  /// In en, this message translates to:
  /// **'No upcoming tasks.'**
  String get nothingUpcoming;

  /// No description provided for @nothingHere.
  ///
  /// In en, this message translates to:
  /// **'Nothing here.'**
  String get nothingHere;

  /// No description provided for @overdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get overdue;

  /// No description provided for @dueToday.
  ///
  /// In en, this message translates to:
  /// **'Due today'**
  String get dueToday;

  /// No description provided for @pinned.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get pinned;

  /// No description provided for @completedToday.
  ///
  /// In en, this message translates to:
  /// **'Completed today'**
  String get completedToday;

  /// No description provided for @tomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get tomorrow;

  /// No description provided for @thisWeek.
  ///
  /// In en, this message translates to:
  /// **'This Week'**
  String get thisWeek;

  /// No description provided for @nextWeek.
  ///
  /// In en, this message translates to:
  /// **'Next Week'**
  String get nextWeek;

  /// No description provided for @laterThisMonth.
  ///
  /// In en, this message translates to:
  /// **'Later This Month'**
  String get laterThisMonth;

  /// No description provided for @future.
  ///
  /// In en, this message translates to:
  /// **'Future'**
  String get future;

  /// No description provided for @newProject.
  ///
  /// In en, this message translates to:
  /// **'New project'**
  String get newProject;

  /// No description provided for @newFolder.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get newFolder;

  /// No description provided for @newList.
  ///
  /// In en, this message translates to:
  /// **'New task list'**
  String get newList;

  /// No description provided for @newWorkspace.
  ///
  /// In en, this message translates to:
  /// **'New workspace'**
  String get newWorkspace;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @moveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get moveUp;

  /// No description provided for @moveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get moveDown;

  /// No description provided for @complete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get complete;

  /// No description provided for @reopen.
  ///
  /// In en, this message translates to:
  /// **'Reopen'**
  String get reopen;

  /// No description provided for @sendToTrash.
  ///
  /// In en, this message translates to:
  /// **'Move to Trash'**
  String get sendToTrash;

  /// No description provided for @invalidEntry.
  ///
  /// In en, this message translates to:
  /// **'Check the entered values.'**
  String get invalidEntry;

  /// No description provided for @weekStartsMonday.
  ///
  /// In en, this message translates to:
  /// **'Weeks start on Monday.'**
  String get weekStartsMonday;

  /// No description provided for @syncDisabled.
  ///
  /// In en, this message translates to:
  /// **'Local-network sync is disabled.'**
  String get syncDisabled;

  /// No description provided for @notesLater.
  ///
  /// In en, this message translates to:
  /// **'Notes and audio arrive in a later phase.'**
  String get notesLater;

  /// No description provided for @shortcuts.
  ///
  /// In en, this message translates to:
  /// **'Ctrl+N task · Ctrl+Shift+N project · Ctrl+F search · Ctrl+1/2/3 navigate · Ctrl+Shift+S sticky'**
  String get shortcuts;

  /// No description provided for @stickyEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tasks for today.'**
  String get stickyEmpty;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @projectList.
  ///
  /// In en, this message translates to:
  /// **'Project or task list'**
  String get projectList;

  /// No description provided for @tags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tags;

  /// No description provided for @subtasks.
  ///
  /// In en, this message translates to:
  /// **'Subtasks'**
  String get subtasks;

  /// No description provided for @parentTask.
  ///
  /// In en, this message translates to:
  /// **'Parent task'**
  String get parentTask;

  /// No description provided for @reminderDate.
  ///
  /// In en, this message translates to:
  /// **'Reminder date (YYYY-MM-DD)'**
  String get reminderDate;

  /// No description provided for @recurrence.
  ///
  /// In en, this message translates to:
  /// **'Recurrence rule'**
  String get recurrence;

  /// No description provided for @pinTask.
  ///
  /// In en, this message translates to:
  /// **'Pin task'**
  String get pinTask;

  /// No description provided for @move.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get move;

  /// No description provided for @moveTo.
  ///
  /// In en, this message translates to:
  /// **'Move to'**
  String get moveTo;

  /// No description provided for @moveLeft.
  ///
  /// In en, this message translates to:
  /// **'Move to parent'**
  String get moveLeft;

  /// No description provided for @moveRight.
  ///
  /// In en, this message translates to:
  /// **'Move into previous sibling'**
  String get moveRight;

  /// No description provided for @hierarchyActions.
  ///
  /// In en, this message translates to:
  /// **'Hierarchy actions'**
  String get hierarchyActions;

  /// No description provided for @invalidHierarchyError.
  ///
  /// In en, this message translates to:
  /// **'That hierarchy move is not allowed.'**
  String get invalidHierarchyError;

  /// No description provided for @invalidDatesError.
  ///
  /// In en, this message translates to:
  /// **'Check the start, due, and reminder dates.'**
  String get invalidDatesError;

  /// No description provided for @missingNodeError.
  ///
  /// In en, this message translates to:
  /// **'That item no longer exists.'**
  String get missingNodeError;

  /// No description provided for @staleRevisionError.
  ///
  /// In en, this message translates to:
  /// **'This item changed elsewhere. Refresh and try again.'**
  String get staleRevisionError;

  /// No description provided for @duplicateTagError.
  ///
  /// In en, this message translates to:
  /// **'A tag with that name already exists.'**
  String get duplicateTagError;

  /// No description provided for @databaseError.
  ///
  /// In en, this message translates to:
  /// **'The local change could not be saved.'**
  String get databaseError;

  /// No description provided for @retentionError.
  ///
  /// In en, this message translates to:
  /// **'That permanent deletion is not allowed.'**
  String get retentionError;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// No description provided for @allPriorities.
  ///
  /// In en, this message translates to:
  /// **'All priorities'**
  String get allPriorities;

  /// No description provided for @selectedTaskHint.
  ///
  /// In en, this message translates to:
  /// **'Selected task: Ctrl+Enter complete · Ctrl+E edit · Delete Trash'**
  String get selectedTaskHint;

  /// No description provided for @noParent.
  ///
  /// In en, this message translates to:
  /// **'No parent'**
  String get noParent;

  /// No description provided for @noProject.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get noProject;

  /// No description provided for @createTag.
  ///
  /// In en, this message translates to:
  /// **'Create tag'**
  String get createTag;

  /// No description provided for @archivedProjects.
  ///
  /// In en, this message translates to:
  /// **'Archived hierarchy'**
  String get archivedProjects;

  /// No description provided for @trashedProjects.
  ///
  /// In en, this message translates to:
  /// **'Trashed hierarchy'**
  String get trashedProjects;

  /// No description provided for @restoreHierarchy.
  ///
  /// In en, this message translates to:
  /// **'Restore hierarchy'**
  String get restoreHierarchy;

  /// No description provided for @hierarchyShortcutHint.
  ///
  /// In en, this message translates to:
  /// **'Hierarchy: F2 rename · Alt+M move · Alt+↑/↓ reorder'**
  String get hierarchyShortcutHint;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @audio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get audio;

  /// No description provided for @noteTitle.
  ///
  /// In en, this message translates to:
  /// **'Note title'**
  String get noteTitle;

  /// No description provided for @noteBody.
  ///
  /// In en, this message translates to:
  /// **'Write a note…'**
  String get noteBody;

  /// No description provided for @newNote.
  ///
  /// In en, this message translates to:
  /// **'New note'**
  String get newNote;

  /// No description provided for @openQuickNote.
  ///
  /// In en, this message translates to:
  /// **'Open Quick Note'**
  String get openQuickNote;

  /// No description provided for @searchNotes.
  ///
  /// In en, this message translates to:
  /// **'Search notes'**
  String get searchNotes;

  /// No description provided for @noNotes.
  ///
  /// In en, this message translates to:
  /// **'No notes here.'**
  String get noNotes;

  /// No description provided for @selectNote.
  ///
  /// In en, this message translates to:
  /// **'Select or create a note.'**
  String get selectNote;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saving;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @words.
  ///
  /// In en, this message translates to:
  /// **'words'**
  String get words;

  /// No description provided for @characters.
  ///
  /// In en, this message translates to:
  /// **'characters'**
  String get characters;

  /// No description provided for @monospace.
  ///
  /// In en, this message translates to:
  /// **'Monospace'**
  String get monospace;

  /// No description provided for @vaultUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The vault is unavailable. Editing is paused.'**
  String get vaultUnavailable;

  /// No description provided for @record.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get record;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @noAudio.
  ///
  /// In en, this message translates to:
  /// **'No audio notes yet.'**
  String get noAudio;

  /// No description provided for @audioError.
  ///
  /// In en, this message translates to:
  /// **'Audio operation failed'**
  String get audioError;

  /// No description provided for @audioPlaybackLimits.
  ///
  /// In en, this message translates to:
  /// **'WAV playback has no seek, volume, pause, or completion callback.'**
  String get audioPlaybackLimits;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @openMain.
  ///
  /// In en, this message translates to:
  /// **'Open main app'**
  String get openMain;

  /// No description provided for @compactMode.
  ///
  /// In en, this message translates to:
  /// **'Compact mode'**
  String get compactMode;

  /// No description provided for @collapseCompleted.
  ///
  /// In en, this message translates to:
  /// **'Collapse completed'**
  String get collapseCompleted;

  /// No description provided for @linkedProjectId.
  ///
  /// In en, this message translates to:
  /// **'Linked project/list ID'**
  String get linkedProjectId;

  /// No description provided for @linkedTaskId.
  ///
  /// In en, this message translates to:
  /// **'Linked task ID'**
  String get linkedTaskId;

  /// No description provided for @policyArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get policyArchive;

  /// No description provided for @policyTrash.
  ///
  /// In en, this message translates to:
  /// **'Move to Trash'**
  String get policyTrash;

  /// No description provided for @policyKeepCompleted.
  ///
  /// In en, this message translates to:
  /// **'Keep in Completed'**
  String get policyKeepCompleted;

  /// No description provided for @retentionThirtyDays.
  ///
  /// In en, this message translates to:
  /// **'30 days'**
  String get retentionThirtyDays;

  /// No description provided for @retentionNever.
  ///
  /// In en, this message translates to:
  /// **'Keep forever'**
  String get retentionNever;

  /// No description provided for @completionPolicyHint.
  ///
  /// In en, this message translates to:
  /// **'Where a task goes right after you complete it.'**
  String get completionPolicyHint;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageHint.
  ///
  /// In en, this message translates to:
  /// **'The workspace, sticky window, and quick note follow this choice.'**
  String get languageHint;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageTurkish.
  ///
  /// In en, this message translates to:
  /// **'Türkçe'**
  String get languageTurkish;

  /// No description provided for @someday.
  ///
  /// In en, this message translates to:
  /// **'Someday · No date'**
  String get someday;

  /// No description provided for @areYouSure.
  ///
  /// In en, this message translates to:
  /// **'Are you sure?'**
  String get areYouSure;

  /// No description provided for @confirmTrashTask.
  ///
  /// In en, this message translates to:
  /// **'Move this task to Trash?'**
  String get confirmTrashTask;

  /// No description provided for @confirmDeleteForever.
  ///
  /// In en, this message translates to:
  /// **'Delete this task permanently?'**
  String get confirmDeleteForever;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @projectOptional.
  ///
  /// In en, this message translates to:
  /// **'Project (optional)'**
  String get projectOptional;

  /// No description provided for @generalSection.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get generalSection;

  /// No description provided for @generalSectionHint.
  ///
  /// In en, this message translates to:
  /// **'Task lifecycle and workspace behavior'**
  String get generalSectionHint;

  /// No description provided for @completionSection.
  ///
  /// In en, this message translates to:
  /// **'Completion'**
  String get completionSection;

  /// No description provided for @trashRetentionSection.
  ///
  /// In en, this message translates to:
  /// **'Trash retention'**
  String get trashRetentionSection;

  /// No description provided for @backupSection.
  ///
  /// In en, this message translates to:
  /// **'Backup & recovery'**
  String get backupSection;

  /// No description provided for @syncSection.
  ///
  /// In en, this message translates to:
  /// **'Local sync'**
  String get syncSection;

  /// No description provided for @openVaultForBackups.
  ///
  /// In en, this message translates to:
  /// **'Open a vault to manage backups.'**
  String get openVaultForBackups;

  /// No description provided for @syncLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Synchronization settings could not be loaded on this device.'**
  String get syncLoadFailed;

  /// No description provided for @linkedTask.
  ///
  /// In en, this message translates to:
  /// **'Linked task (optional)'**
  String get linkedTask;

  /// No description provided for @noLinkedTask.
  ///
  /// In en, this message translates to:
  /// **'No linked task'**
  String get noLinkedTask;

  /// No description provided for @taskStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get taskStatusOpen;

  /// No description provided for @taskStatusInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get taskStatusInProgress;

  /// No description provided for @taskStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get taskStatusCompleted;

  /// No description provided for @taskStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get taskStatusCancelled;

  /// No description provided for @stickySourceToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get stickySourceToday;

  /// No description provided for @stickySourceTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get stickySourceTomorrow;

  /// No description provided for @stickySourceThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get stickySourceThisWeek;

  /// No description provided for @stickySourceProject.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get stickySourceProject;

  /// No description provided for @stickySourceFolderOrList.
  ///
  /// In en, this message translates to:
  /// **'Folder or list'**
  String get stickySourceFolderOrList;

  /// No description provided for @stickySourcePinned.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get stickySourcePinned;

  /// No description provided for @themeSection.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeSection;

  /// No description provided for @themeSectionHint.
  ///
  /// In en, this message translates to:
  /// **'Applies to the workspace and companion windows.'**
  String get themeSectionHint;

  /// No description provided for @themeObsidianBlack.
  ///
  /// In en, this message translates to:
  /// **'Obsidian Black'**
  String get themeObsidianBlack;

  /// No description provided for @themeGraphite.
  ///
  /// In en, this message translates to:
  /// **'Graphite'**
  String get themeGraphite;

  /// No description provided for @themeMidnightIndigo.
  ///
  /// In en, this message translates to:
  /// **'Midnight Indigo'**
  String get themeMidnightIndigo;

  /// No description provided for @themeNordicLight.
  ///
  /// In en, this message translates to:
  /// **'Nordic Light'**
  String get themeNordicLight;

  /// No description provided for @themeWarmPaper.
  ///
  /// In en, this message translates to:
  /// **'Warm Paper'**
  String get themeWarmPaper;

  /// No description provided for @addNote.
  ///
  /// In en, this message translates to:
  /// **'Add note'**
  String get addNote;

  /// No description provided for @addTask.
  ///
  /// In en, this message translates to:
  /// **'Add task'**
  String get addTask;

  /// No description provided for @moveToProject.
  ///
  /// In en, this message translates to:
  /// **'Move to project'**
  String get moveToProject;

  /// No description provided for @assignToProject.
  ///
  /// In en, this message translates to:
  /// **'Assign to project'**
  String get assignToProject;

  /// No description provided for @searchProjectsSection.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get searchProjectsSection;

  /// No description provided for @searchTasksSection.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get searchTasksSection;

  /// No description provided for @backupTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup & recovery'**
  String get backupTitle;

  /// No description provided for @backupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Portable, verified copies of the complete vault'**
  String get backupSubtitle;

  /// No description provided for @backupCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create vault backup'**
  String get backupCreateTitle;

  /// No description provided for @backupCreateBody.
  ///
  /// In en, this message translates to:
  /// **'Export a consistent database snapshot with notes, audio, attachments, and a SHA-256 integrity manifest.'**
  String get backupCreateBody;

  /// No description provided for @backupCreateButton.
  ///
  /// In en, this message translates to:
  /// **'Choose export folder'**
  String get backupCreateButton;

  /// No description provided for @backupRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore safely'**
  String get backupRestoreTitle;

  /// No description provided for @backupRestoreBody.
  ///
  /// In en, this message translates to:
  /// **'Validate archive paths, versions, hashes, and SQLite integrity before creating a separate vault.'**
  String get backupRestoreBody;

  /// No description provided for @backupRestoreButton.
  ///
  /// In en, this message translates to:
  /// **'Choose backup file'**
  String get backupRestoreButton;

  /// No description provided for @backupSafetyNote.
  ///
  /// In en, this message translates to:
  /// **'Backups are not encrypted. Store them as carefully as the original vault. Restore detects corruption and unsafe paths; it does not attempt automatic database repair.'**
  String get backupSafetyNote;

  /// No description provided for @backupChooseExportFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose an export folder'**
  String get backupChooseExportFolder;

  /// No description provided for @backupChooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose an ephtodo backup'**
  String get backupChooseFile;

  /// No description provided for @backupChooseRestoreParent.
  ///
  /// In en, this message translates to:
  /// **'Choose a parent folder for the restored vault'**
  String get backupChooseRestoreParent;

  /// No description provided for @backupRestoreConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore into a new vault?'**
  String get backupRestoreConfirmTitle;

  /// No description provided for @backupRestoreConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'ephtodo will validate every file and create a new vault folder. Your active vault will not be changed or overwritten.'**
  String get backupRestoreConfirmBody;

  /// No description provided for @backupValidateRestore.
  ///
  /// In en, this message translates to:
  /// **'Validate & restore'**
  String get backupValidateRestore;

  /// No description provided for @backupFailedGeneric.
  ///
  /// In en, this message translates to:
  /// **'The operation failed without changing the active vault.'**
  String get backupFailedGeneric;

  /// No description provided for @syncHeadline.
  ///
  /// In en, this message translates to:
  /// **'Local sync'**
  String get syncHeadline;

  /// No description provided for @syncHeadlineHint.
  ///
  /// In en, this message translates to:
  /// **'Private-LAN foundation for a future mobile client'**
  String get syncHeadlineHint;

  /// No description provided for @syncSecureServer.
  ///
  /// In en, this message translates to:
  /// **'Secure server'**
  String get syncSecureServer;

  /// No description provided for @syncSecureServerHint.
  ///
  /// In en, this message translates to:
  /// **'Disabled by default. No cloud relay, public tunnel, UPnP, or wildcard binding.'**
  String get syncSecureServerHint;

  /// No description provided for @syncServerAvailable.
  ///
  /// In en, this message translates to:
  /// **'Server is available'**
  String get syncServerAvailable;

  /// No description provided for @syncServerOff.
  ///
  /// In en, this message translates to:
  /// **'Server is off'**
  String get syncServerOff;

  /// No description provided for @syncStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get syncStop;

  /// No description provided for @syncEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get syncEnable;

  /// No description provided for @syncRestoreOnLaunch.
  ///
  /// In en, this message translates to:
  /// **'Restore server on launch'**
  String get syncRestoreOnLaunch;

  /// No description provided for @syncRestoreOnLaunchHint.
  ///
  /// In en, this message translates to:
  /// **'Only after this explicit opt-in; invalid credentials fail closed.'**
  String get syncRestoreOnLaunchHint;

  /// No description provided for @syncPassword.
  ///
  /// In en, this message translates to:
  /// **'Synchronization password'**
  String get syncPassword;

  /// No description provided for @syncPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Argon2id protected in Windows secure storage'**
  String get syncPasswordHint;

  /// No description provided for @syncSetOrChange.
  ///
  /// In en, this message translates to:
  /// **'Set or change'**
  String get syncSetOrChange;

  /// No description provided for @syncPort.
  ///
  /// In en, this message translates to:
  /// **'Port {port}'**
  String syncPort(Object port);

  /// No description provided for @syncPortHint.
  ///
  /// In en, this message translates to:
  /// **'Allowed private/dynamic range: 49152–65535'**
  String get syncPortHint;

  /// No description provided for @syncChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get syncChange;

  /// No description provided for @syncTlsFingerprint.
  ///
  /// In en, this message translates to:
  /// **'TLS fingerprint'**
  String get syncTlsFingerprint;

  /// No description provided for @syncCopyFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Copy fingerprint'**
  String get syncCopyFingerprint;

  /// No description provided for @syncPairing.
  ///
  /// In en, this message translates to:
  /// **'Pairing'**
  String get syncPairing;

  /// No description provided for @syncPairingHint.
  ///
  /// In en, this message translates to:
  /// **'Codes expire after five minutes, work once, and still require desktop approval.'**
  String get syncPairingHint;

  /// No description provided for @syncCreatePairingCode.
  ///
  /// In en, this message translates to:
  /// **'Create pairing code'**
  String get syncCreatePairingCode;

  /// No description provided for @syncPairedDevices.
  ///
  /// In en, this message translates to:
  /// **'Paired devices'**
  String get syncPairedDevices;

  /// No description provided for @syncNoPairedDevices.
  ///
  /// In en, this message translates to:
  /// **'No devices are paired yet.'**
  String get syncNoPairedDevices;

  /// No description provided for @syncApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get syncApprove;

  /// No description provided for @syncReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get syncReject;

  /// No description provided for @syncRevoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get syncRevoke;

  /// No description provided for @stickyEmptyFiltered.
  ///
  /// In en, this message translates to:
  /// **'No tasks for this view.'**
  String get stickyEmptyFiltered;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'tr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'tr':
      return AppLocalizationsTr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
