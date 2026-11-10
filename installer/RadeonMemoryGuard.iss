#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef SourceRoot
  #define SourceRoot ".."
#endif
#ifndef BuildRoot
  #define BuildRoot "..\build"
#endif

[Setup]
AppId={{E125617D-30D3-41B4-B216-F758FF90B8C0}
AppName=Radeon Memory Guard
AppVersion={#AppVersion}
AppVerName=Radeon Memory Guard {#AppVersion} (Experimental)
AppPublisher=JZB Apps
AppPublisherURL=https://jzbapps.com
AppSupportURL=mailto:support@jzbapps.com
AppUpdatesURL=https://jzbapps.com/apps/radeon-memory-guard/
VersionInfoDescription=JZB Apps Radeon Memory Guard (Experimental) Setup
VersionInfoVersion={#AppVersion}.0
VersionInfoProductVersion={#AppVersion}
DefaultDirName={autopf}\JZB Apps\Radeon Memory Guard
DisableDirPage=yes
UsePreviousAppDir=no
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir={#BuildRoot}
OutputBaseFilename=RadeonMemoryGuard-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile={#SourceRoot}\branding\jzb-apps.ico
WizardImageFile={#SourceRoot}\branding\wizard-large.png
WizardSmallImageFile={#SourceRoot}\branding\wizard-small.png
DisableWelcomePage=no
LicenseFile={#SourceRoot}\LICENSE
InfoBeforeFile={#SourceRoot}\installer\SetupNotes.txt
SetupLogging=yes
AlwaysRestart=no
RestartIfNeededByRun=no
CloseApplications=no
RestartApplications=no
#ifdef SelfSign
SignTool=JzbOwn
SignedUninstaller=yes
#else
SignedUninstaller=no
#endif
UninstallDisplayName=Radeon Memory Guard (Experimental)
UninstallDisplayIcon={uninstallexe}

[Messages]
WelcomeLabel2=Maintain the workaround for an identified Radeon memory leak and redirect repeated executable-cache writes to RAM.
InfoBeforeLabel=Compatibility and risks
InfoBeforeClickLabel=

[Types]
Name: "full"; Description: "Memory protection and RAM write redirection"
Name: "custom"; Description: "Choose protection"; Flags: iscustom

[Components]
Name: "core"; Description: "Memory workaround and automatic maintenance"; Types: full custom; Flags: fixed
Name: "ram"; Description: "Redirect repeated AMD cache writes to 64 MiB RAM (includes free signed storage dependencies)"; Types: full

[Files]
Source: "{#SourceRoot}\RadeonMemoryGuard.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\RadeonMemoryGuard.psm1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\RadeonRamCache.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\RadeonStorage.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\VALIDATION.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\VERSION"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\THIRD-PARTY-NOTICES.txt"; DestDir: "{app}"; Flags: ignoreversion
#ifdef OfflinePayloadDir
Source: "{#OfflinePayloadDir}\Arsenal-DriverFiles.zip"; DestDir: "{tmp}\rmg-payload"; Components: ram; Flags: deleteafterinstall
Source: "{#OfflinePayloadDir}\Arsenal-Image-Mounter-source.zip"; DestDir: "{app}\third-party"; Components: ram; Flags: ignoreversion
#endif

[Icons]
Name: "{commonprograms}\Radeon Memory Guard\Instructions"; Filename: "{app}\README.md"
Name: "{commonprograms}\Radeon Memory Guard\Restore and uninstall"; Filename: "{uninstallexe}"
Name: "{commonprograms}\Radeon Memory Guard\JZB Apps website"; Filename: "https://jzbapps.com"
Name: "{commonprograms}\Radeon Memory Guard\Email support"; Filename: "mailto:support@jzbapps.com"

[Code]
var
  ConfigurationSucceeded: Boolean;
  FailureText: String;
  ContactLinks: TNewLinkLabel;

procedure ContactLinkClick(Sender: TObject; const Link: string; LinkType: TSysLinkType);
var
  ErrorCode: Integer;
begin
  if (LinkType = sltURL) and ((Link = 'https://jzbapps.com') or (Link = 'mailto:support@jzbapps.com')) then
    ShellExecAsOriginalUser('open', Link, '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
end;

function RunGuard(Action: String): Boolean;
var
  ExitCode: Integer;
  Args: String;
begin
  Args := '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File "' +
    ExpandConstant('{app}\RadeonMemoryGuard.ps1') + '" -Action ' + Action + ' -Quiet';
#ifdef OfflinePayloadDir
  if Action = 'InstallRamBackend' then
  begin
    Args := Args + ' -Offline -PayloadRoot "' + ExpandConstant('{tmp}\rmg-payload') + '"';
    Log('Preparing RAM-storage drivers.');
  end;
#endif
  Log('Running guard action: ' + Action);
  Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    Args, ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ExitCode);
  if Result then Result := ExitCode = 0;
  Log(Format('Guard action %s exit code: %d', [Action, ExitCode]));
end;

procedure InitializeWizard;
begin
  ConfigurationSucceeded := False;
  WizardForm.SelectComponentsLabel.Caption := 'Choose protection.';
  ContactLinks := TNewLinkLabel.Create(WizardForm);
  ContactLinks.Parent := WizardForm;
  ContactLinks.Left := ScaleX(12);
  ContactLinks.Top := WizardForm.CancelButton.Top + ScaleY(4);
  ContactLinks.Width := ScaleX(260);
  ContactLinks.Height := ScaleY(20);
  ContactLinks.Caption := '<a href="https://jzbapps.com">jzbapps.com</a>  |  <a href="mailto:support@jzbapps.com">Email support</a>';
  ContactLinks.OnLinkClick := @ContactLinkClick;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  LedgerPath: String;
  Ledger: AnsiString;
  CompactLedger: String;
begin
  Result := '';
  if CompareText(WizardDirValue, ExpandConstant('{autopf}\JZB Apps\Radeon Memory Guard')) <> 0 then
    Result := 'Install to the protected default Program Files location.';
  LedgerPath := ExpandConstant('{commonappdata}\JZBApps-RadeonMemoryGuard\ram-cache.json');
  if FileExists(LedgerPath) then begin
    if not LoadStringFromFile(LedgerPath, Ledger) then
      Result := 'The existing RAM-cache ledger could not be inspected. Setup made no changes.'
    else begin
      CompactLedger := String(Ledger);
      StringChangeEx(CompactLedger, ' ', '', True);
      StringChangeEx(CompactLedger, #9, '', True);
      StringChangeEx(CompactLedger, #13, '', True);
      StringChangeEx(CompactLedger, #10, '', True);
      if Pos('"Provider":"Arsenal"', CompactLedger) = 0 then
        Result := 'The existing RAM setup uses a different backend. Restore and uninstall that version, retain its recovery files, and archive its inactive ram-cache.json before installing this version. Setup made no changes.';
    end;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    WizardForm.StatusLabel.Caption := 'Configuring automatic protection...';
    if WizardIsComponentSelected('ram') and not RunGuard('InstallRamBackend') then
      FailureText := 'The signed RAM-storage dependencies could not be prepared.'
    else if not RunGuard('Install') then
      FailureText := 'Automatic maintenance could not be configured.'
    else if WizardIsComponentSelected('ram') and not RunGuard('ProtectSsdRam') then
      FailureText := 'RAM write redirection could not be enabled.'
    else
      ConfigurationSucceeded := True;
    if not ConfigurationSucceeded then begin
      FailureText := FailureText + #13#10#13#10 +
        'Files and recovery backups were retained. See C:\ProgramData\JZBApps-RadeonMemoryGuard\last-error.json and the setup log. Correct the issue and run Setup again, or use Restore and uninstall. Windows has not been restarted.';
      Log(FailureText);
      SuppressibleMsgBox(FailureText, mbError, MB_OK, IDOK);
    end;
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then begin
    if ConfigurationSucceeded then
      WizardForm.FinishedLabel.Caption := 'Radeon Memory Guard is installed.'
    else begin
      WizardForm.FinishedHeadingLabel.Caption := 'Setup needs attention';
      WizardForm.FinishedLabel.Caption := FailureText;
    end;
  end;
end;

function GetCustomSetupExitCode: Integer;
begin
  Result := 0;
  if not ConfigurationSucceeded then Result := 10;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then begin
    if not RunGuard('Uninstall') then begin
      SuppressibleMsgBox('Restoration failed. The installed recovery files and uninstaller have been retained. See C:\ProgramData\JZBApps-RadeonMemoryGuard\last-error.json. Resolve the conflict and retry uninstall.', mbError, MB_OK, IDOK);
      Abort;
    end;
  end;
end;
