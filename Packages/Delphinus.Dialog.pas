{
#########################################################
# Copyright by Alexander Benikowski                     #
# This unit is part of the Delphinus project hosted on  #
# https://github.com/Memnarch/Delphinus                 #
#########################################################
}
unit Delphinus.Dialog;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics,
  Controls, Forms, Dialogs,
  DN.PackageOverview, ActnList, ImgList, ToolWin,
  ComCtrls,
  DN.PackageProvider.Intf,
  DN.Package.Intf,
  ContNrs,
  Generics.Collections,
  DN.PackageDetailView,
  Delphinus.Forms,
  DN.Settings.Intf,
  DN.Setup.Intf,
  DN.FileService.Intf,
  Delphinus.CategoryFilterView,
  Delphinus.ProgressDialog,
  DN.PackageFilter,
  DN.Version,
  DN.EnvironmentOptions.Intf,
  ExtCtrls,
  StdCtrls,
  Registry;

type
  TDelphinusDialog = class(TForm)
    ToolBar1: TToolBar;
    ilMenu: TImageList;
    DialogActions: TActionList;
    ToolButton1: TToolButton;
    actRefresh: TAction;
    ToolButton2: TToolButton;
    btnInstallFolder: TToolButton;
    dlgSelectInstallFile: TOpenDialog;
    dlgSelectUninstallFile: TOpenDialog;
    actOptions: TAction;
    pnlPackages: TPanel;
    edSearch: TButtonedEdit;
    ilSmall: TImageList;
    pnlToolBar: TPanel;
    actInstallFolder: TAction;
    actAbout: TAction;
    btnAbout: TToolButton;
    procedure actRefreshExecute(Sender: TObject);
    procedure btnInstallFolderClick(Sender: TObject);
    procedure actOptionsExecute(Sender: TObject);
    procedure FormMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure edSearchKeyPress(Sender: TObject; var Key: Char);
    procedure edSearchRightButtonClick(Sender: TObject);
    procedure edSearchLeftButtonClick(Sender: TObject);
    procedure actAboutExecute(Sender: TObject);
  private
    { Private declarations }
    FOverView: TPackageOverView;
    FPackageProvider: IDNPackageProvider;
    FInstalledPackageProvider: IDNPackageProvider;
    FPackages: TList<IDNPackage>;
    FInstalledPackages: TList<IDNPackage>;
    FUpdatePackages: TList<IDNPackage>;
    FDetailView: TPackageDetailView;
    FSettings: IDNSettings;
    FCategoryFilteView: TCategoryFilterView;
    FCategory: TPackageCategory;
    FProgressDialog: TProgressDialog;
    FFilter: string;
    FFileService: IDNFileService;
    FDummyPic: TGraphic;
    FEnvironmentOptionsService: IDNEnvironmentOptionsService;
    procedure InstallPackage(const APackage: IDNPackage);
    procedure UnInstallPackage(const APackage: IDNPackage);
    procedure UpdatePackage(const APackage: IDNPackage);
    function GetComponentDirectory: string;
    function GetBPLDirectory: string;
    function GetDCPDirectory: string;
    procedure RefreshInstalledPackages;
    function IsPackageInstalled(const APackage: IDNPackage): Boolean;
    function GetInstalledPackage(const APackage: IDNPackage): IDNPackage;
    function GetOnlinePackage(const APackage: IDNPackage): IDNPackage;
    function GetInstalledVersion(const APackage: IDNPackage): TDNVersion;
    function GetUpdateVersion(const APackage: IDNPackage): TDNVersion;
    function GetActiveOverView: TPackageOverView;
    procedure ShowDetail(const APackage: IDNPackage);
    procedure RecreatePackageProvider();
    function CreateSetup: IDNSetup;
    function IsStarter: Boolean;
    procedure HandleCategoryChanged(Sender: TObject; ANewCategory: TPackageCategory);
    procedure HandleSelectedPackageChanged(Sender: TObject);
    procedure HandleAsyncProgress(const ATask, AItem: string; AProgress, AMax: Int64);
    function GetActivePackageSource: TList<IDNPackage>;
    procedure RefreshOverview();
    procedure DoFilter(const AFilter: string);
    procedure FilterPackage(const APackage: IDNPackage; var AAccepted: Boolean);
    procedure LoadIcons;
  public
    { Public declarations }
    constructor Create(AOwner: TComponent); override;
    destructor Destroy(); override;
  end;

var
  DelphinusDialog: TDelphinusDialog;

implementation

uses
  ToolsApi,
  IOUtils,
  RTTI,
  Types,
  PNGImage,
  DN.Types,
  DN.PackageProvider.GitHub,
  DN.PackageProvider.Installed,
  Delphinus.SetupDialog,
  DN.Compiler.Intf,
  DN.Compiler.MSBuild,
  DN.Compiler.IDE,
  DN.Installer.Intf,
  DN.Installer.IDE,
  DN.Uninstaller.Intf,
  DN.Uninstaller.IDE,
  DN.Setup,
  Delphinus.OptionsDialog,
  DN.HttpClient.Intf,
  DN.HttpClient.WinHttp,
  DN.Progress.Intf,
  DN.Settings,
  DN.ExpertService,
  DN.ExpertService.Intf,
  DN.FileService,
  DN.EnvironmentOptions.IDE,
  DN.BPLService.Intf,
  DN.BPLService.ToolsApi,
  Delphinus.Resources.Names,
  Delphinus.Resources,
  Delphinus.About,
  StrUtils;

{$R *.dfm}

const
  CDelphinusSubKey = 'Delphinus';
  CFiltersSubKey = 'Filters';
  COAuthTokenKey = 'OAuthToken';

{ TDelphinusDialog }

procedure TDelphinusDialog.actAboutExecute(Sender: TObject);
var
  LDialog: TAboutDialog;
begin
  LDialog := TAboutDialog.Create(nil);
  try
    LDialog.ShowModal();
  finally
    LDialog.Free;
  end;
end;

procedure TDelphinusDialog.actOptionsExecute(Sender: TObject);
var
  LDialog: TDelphinusOptionsDialog;
begin
  LDialog := TDelphinusOptionsDialog.Create(nil);
  try
    LDialog.LoadSettings(FSettings);
    if LDialog.ShowModal = mrOk then
    begin
      LDialog.StoreSettings(FSettings);
      RecreatePackageProvider();
    end;
  finally
    LDialog.Free;
  end;
end;

procedure TDelphinusDialog.actRefreshExecute(Sender: TObject);
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      LProgress: IDNProgress;
    begin
      try
        if Supports(FPackageProvider, IDNProgress, LProgress) then
          LProgress.OnProgress := HandleAsyncProgress;
        if FPackageProvider.Reload() then
        begin
          FPackages.Clear;
          FPackages.AddRange(FPackageProvider.Packages);
        end;
      finally
        if Assigned(LProgress) then
          LProgress.OnProgress := nil;
        TThread.Queue(nil,
          procedure
          begin
            FCategoryFilteView.OnlineCount := FPackages.Count;
            RefreshInstalledPackages();
            FProgressDialog.ModalResult := mrOk;
          end);
      end;
    end).Start;
  FProgressDialog.Caption := 'Delphinus';
  FProgressDialog.Task := 'Refreshing';
  FProgressDialog.Progress := -1;
  FProgressDialog.ShowModal();
end;

procedure TDelphinusDialog.btnInstallFolderClick(Sender: TObject);
var
  LDialog: TSetupDialog;
begin
  if dlgSelectInstallFile.Execute() then
  begin
    LDialog := TSetupDialog.Create(CreateSetup());
    try
      if LDialog.ExecuteInstallationFromDirectory(ExtractFilePath(dlgSelectInstallFile.FileName)) then
        RefreshInstalledPackages();
    finally
      LDialog.Free;
    end;
  end;
end;

constructor TDelphinusDialog.Create(AOwner: TComponent);
begin
  inherited;
  FSettings := TDNSettings.Create();
  FPackages := TList<IDNPackage>.Create();
  FInstalledPackages := TList<IDNPackage>.Create();
  FUpdatePackages := TList<IDNPackage>.Create();
  FFileService := TDNFileService.Create((BorlandIDEServices as IOTAServices).GetBaseRegistryKey);
  FEnvironmentOptionsService := TDNEnvironmentOptionsService.Create();

  FProgressDialog := TProgressDialog.Create(Self);
  FDetailView := TPackageDetailView.Create(Self);
  FDetailView.OnGetOnlineVersion := GetUpdateVersion;
  FDetailView.OnGetInstalledVersion := GetInstalledVersion;
  FDetailView.Align := alRight;
  FDetailView.Parent := Self;

  FOverView := TPackageOverView.Create(Self);
  FOverView.Align := alClient;
  FOverView.Parent := pnlPackages;
  FOverView.OnCheckIsPackageInstalled := GetInstalledVersion;
  FOverView.OnCheckHasPackageUpdate := GetUpdateVersion;
  FOverView.OnSelectedPackageChanged := HandleSelectedPackageChanged;
  FOverView.OnInstallPackage :=  InstallPackage;
  FOverView.OnUninstallPackage := UninstallPackage;
  FOverView.OnUpdatePackage := UpdatePackage;
  FOverView.DoubleBuffered := True;
  FOverView.OnFilter := FilterPackage;
  FCategoryFilteView := TCategoryFilterView.Create(Self);
  FCategoryFilteView.Width := 200;
  FCategoryFilteView.Align := alLeft;
  FCategoryFilteView.OnCategoryChanged := HandleCategoryChanged;
  FCategoryFilteView.Parent := Self;

  RecreatePackageProvider();
  FInstalledPackageProvider := TDNInstalledPackageProvider.Create(GetComponentDirectory());
  RefreshInstalledPackages();
  dlgSelectInstallFile.Filter := CInstallFileFilter;
  dlgSelectUninstallFile.Filter := CUninstallFileFilter;

  //adjust serachbar to be over the Packagelist
  edSearch.Width := pnlPackages.Width;
  edSearch.Left := pnlPackages.Left;

  LoadIcons();

  FFileService.Cleanup();
  if IsStarter then
    Caption := Caption + ' (Starter Edition)';
end;

function TDelphinusDialog.CreateSetup: IDNSetup;
var
  LCompiler: IDNCompiler;
  LInstaller: IDNInstaller;
  LUninstaller: IDNUninstaller;
  LExpertService: IDNExpertService;
  LBPLService: IDNBPLService;
begin
  if IsStarter then
    LCompiler := TDNIDECompiler.Create()
  else
    LCompiler := TDNMSBuildCompiler.Create(GetEnvironmentVariable('BDSBIN'));
  LCompiler.BPLOutput := GetBPLDirectory();
  LCompiler.DCPOutput := GetDCPDirectory();
  LExpertService := TDNExpertService.Create((BorlandIDEServices as IOTAServices).GetBaseRegistryKey());
  LBPLService := TDNToolsApiBPLService.Create();
  LInstaller := TDNIDEInstaller.Create(LCompiler, FEnvironmentOptionsService, LBPLService, LExpertService);
  LUninstaller := TDNIDEUninstaller.Create(FEnvironmentOptionsService, LBPLService, LExpertService, FFileService);
  Result := TDNSetup.Create(LInstaller, LUninstaller, FPackageProvider);
  Result.ComponentDirectory := GetComponentDirectory();
end;

destructor TDelphinusDialog.Destroy;
begin
  FOverView.OnSelectedPackageChanged := nil;
  FPackages.Free;
  FInstalledPackages.Free;
  FUpdatePackages.Free;
  FPackageProvider := nil;
  FInstalledPackageProvider := nil;
  FSettings := nil;
  FDummyPic.Free;
  inherited;
end;

procedure TDelphinusDialog.DoFilter(const AFilter: string);
begin
  FFilter := Trim(AFilter);
  FOverView.ApplyFilter();
end;

procedure TDelphinusDialog.edSearchKeyPress(Sender: TObject; var Key: Char);
begin
  if Ord(Key) = VK_RETURN then
  begin
    DoFilter(edSearch.Text);
    Key := #0;
  end;

  if Ord(Key) = VK_ESCAPE then
  begin
    edSearch.Text := '';
    DoFilter('');
    Key := #0;
  end;
end;

procedure TDelphinusDialog.edSearchLeftButtonClick(Sender: TObject);
begin
  DoFilter(edSearch.Text);
end;

procedure TDelphinusDialog.edSearchRightButtonClick(Sender: TObject);
begin
  edSearch.Text := '';
  DoFilter('');
end;

procedure TDelphinusDialog.FilterPackage(const APackage: IDNPackage;
  var AAccepted: Boolean);
begin
  AAccepted := ((FFilter = '') or ContainsText(APackage.Name, FFilter));
end;

procedure TDelphinusDialog.FormMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
var
  LPos: TPoint;
  LOverView: TPackageOverView;
begin
  LOverView := GetActiveOverView();
  LPos := LOverView.ScreenToClient(MousePos);
  if PtInRect(Rect(0, 0, LOverView.Width, LOverView.Height), LPos) then
  begin
    LOverView.VertScrollBar.Position := LOverView.VertScrollBar.Position - WheelDelta;
    Handled := True;
  end;
end;

function TDelphinusDialog.GetActiveOverView: TPackageOverView;
begin
  Result := FOverView;
end;

function TDelphinusDialog.GetActivePackageSource: TList<IDNPackage>;
begin
  case FCategory of
    pcOnline: Result := FPackages;
    pcInstalled: Result := FInstalledPackages;
    pcUpdates: Result := FUpdatePackages;
  else
    Result := FPackages;
  end;
end;

function TDelphinusDialog.GetBPLDirectory: string;
begin
  Result := TPath.Combine(GetEnvironmentVariable('BDSCOMMONDIR'), 'Bpl');
end;

function TDelphinusDialog.GetComponentDirectory: string;
begin
  Result := TPath.Combine(GetEnvironmentVariable('BDSCOMMONDIR'), 'Comps');
end;

function TDelphinusDialog.GetDCPDirectory: string;
begin
  Result := TPath.Combine(GetEnvironmentVariable('BDSCOMMONDIR'), 'Dcp');
end;

function TDelphinusDialog.GetInstalledPackage(
  const APackage: IDNPackage): IDNPackage;
var
  LPackage: IDNPackage;
begin
  Result := nil;
  if Assigned(APackage) then
  begin
    for LPackage in FInstalledPackages do
    begin
      if LPackage.ID = APackage.ID then
        Exit(LPackage);
    end;
  end
end;

function TDelphinusDialog.GetInstalledVersion(
  const APackage: IDNPackage): TDNVersion;
var
  LPackage: IDNPackage;
begin
  Result := TDNVersion.Create();
  LPackage := GetInstalledPackage(APackage);
  if Assigned(LPackage) then
  begin
    if LPackage.Versions.Count > 0 then
      Result := LPackage.Versions[0].Value
    else
      Result := TDNVersion.Create(0, 0, 0, 'none');
  end;
end;

function TDelphinusDialog.GetOnlinePackage(
  const APackage: IDNPackage): IDNPackage;
var
  LPackage: IDNPackage;
begin
  Result := nil;
  if Assigned(APackage) then
  begin
    for LPackage in FPackages do
    begin
      if LPackage.ID = APackage.ID then
        Exit(LPackage);
    end;
  end
end;

function TDelphinusDialog.GetUpdateVersion(const APackage: IDNPackage): TDNVersion;
var
  LVersion: TDNVersion;
  LPackage: IDNPackage;
begin
  Result := TDNVersion.Create();
  LVersion := GetInstalledVersion(APackage);
  LPackage := GetOnlinePackage(APackage);
  if Assigned(LPackage)and not LVersion.IsEmpty then
  begin
    if (LPackage.Versions.Count > 0) and (LPackage.Versions[0].Value > LVersion) then
      Result := LPackage.Versions[0].Value;
  end;
end;

procedure TDelphinusDialog.HandleAsyncProgress(const ATask, AItem: string;
  AProgress, AMax: Int64);
begin
  TThread.Queue(nil,
    procedure
    begin
      FProgressDialog.Task := AItem;
      FProgressDialog.Progress := AProgress;
    end
  );
end;

procedure TDelphinusDialog.HandleCategoryChanged(Sender: TObject;
  ANewCategory: TPackageCategory);
begin
  FCategory := ANewCategory;
  RefreshOverview();
end;

procedure TDelphinusDialog.HandleSelectedPackageChanged(Sender: TObject);
begin
  ShowDetail(GetActiveOverView().SelectedPackage);
end;

procedure TDelphinusDialog.InstallPackage(const APackage: IDNPackage);
var
  LDialog: TSetupDialog;
begin
  if Assigned(APackage) then
  begin
    LDialog := TSetupDialog.Create(CreateSetup());
    try
      if LDialog.ExecuteInstallation(APackage) then
        RefreshInstalledPackages();
    finally
      LDialog.Free;
    end;
  end;
end;

function TDelphinusDialog.IsPackageInstalled(
  const APackage: IDNPackage): Boolean;
begin
  Result := Assigned(GetInstalledPackage(APackage));
end;

function TDelphinusDialog.IsStarter: Boolean;
var
  LService: IOTAServices;
  LReg: TRegistry;
  LBase: string;
begin
  Result := False;
  LService := BorlandIDEServices as IOTAServices;
  LBase := LService.GetBaseRegistryKey();
  LReg := TRegistry.Create();
  try
    if LReg.OpenKeyReadOnly(LBase) then
    begin
      if LReg.ValueExists('Edition') then
        Result := SameText(LReg.ReadString('Edition'), 'Starter');
    end;
  finally
    LReg.Free;
  end;
end;

procedure TDelphinusDialog.LoadIcons;
var
  LResStream: TResourceStream;
begin
  actRefresh.ImageIndex := AddIconToImageList(ilMenu, Ico_Refresh);
  actOptions.ImageIndex := AddIconToImageList(ilMenu, Ico_Options);
  actInstallFolder.ImageIndex := AddIconToImageList(ilMenu, Ico_Folder);
  actAbout.ImageIndex := AddIconToImageList(ilMenu, Ico_About);
  edSearch.LeftButton.ImageIndex := AddIconToImageList(ilSmall, Ico_Search);
  edSearch.RightButton.ImageIndex := AddIconToImageList(ilSmall, Ico_Close);
  LResStream := TResourceStream.Create(HInstance, Png_Package, RT_RCDATA);
  try
    FDummyPic := TPngImage.Create();
    FDummyPic.LoadFromStream(LResStream);
  finally
    LResStream.Free;
  end;
  FOverView.DummyPic := FDummyPic;
  FDetailView.DummyPic := FDummyPic;
end;

procedure TDelphinusDialog.RecreatePackageProvider;
var
  LClient: IDNHttpClient;
begin
  LClient := TDNWinHttpClient.Create();
  if FSettings.OAuthToken <> '' then
    LClient.Authentication := Format(CGithubOAuthAuthentication, [FSettings.OAuthToken]);
  FPackageProvider := TDNGitHubPackageProvider.Create(LClient);
end;

procedure TDelphinusDialog.RefreshInstalledPackages;
var
  LInstalledPackage: IDNPackage;
begin
  if FInstalledPackageProvider.Reload() then
  begin
    FInstalledPackages.Clear;
    FInstalledPackages.AddRange(FInstalledPackageProvider.Packages);
    FCategoryFilteView.InstalledCount := FInstalledPackages.Count;
    FUpdatePackages.Clear();
    for LInstalledPackage in FInstalledPackages do
    begin
      if not GetUpdateVersion(LInstalledPackage).IsEmpty then
        FUpdatePackages.Add(LInstalledPackage);
    end;
    FCategoryFilteView.UpdatesCount := FUpdatePackages.Count;
  end;
  RefreshOverview();
end;

procedure TDelphinusDialog.RefreshOverview;
begin
  GetActiveOverView().Clear;
  GetActiveOverView().Packages.AddRange(GetActivePackageSource());
end;

procedure TDelphinusDialog.ShowDetail(const APackage: IDNPackage);
begin
  FDetailView.Package := APackage;
  FDetailView.BringToFront();
end;

procedure TDelphinusDialog.UnInstallPackage(const APackage: IDNPackage);
var
  LDialog: TSetupDialog;
begin
  if Assigned(APackage) then
  begin
    LDialog := TSetupDialog.Create(CreateSetup());
    try
      if LDialog.ExecuteUninstallation(APackage) then
        RefreshInstalledPackages();
    finally
      LDialog.Free;
    end;
  end;
end;

procedure TDelphinusDialog.UpdatePackage(const APackage: IDNPackage);
var
  LDialog: TSetupDialog;
begin
  if Assigned(APackage) then
  begin
    LDialog := TSetupDialog.Create(CreateSetup());
    try
      if LDialog.ExecuteUpdate(GetOnlinePackage(APackage))then
        RefreshInstalledPackages();
    finally
      LDialog.Free;
    end;
  end;
end;

end.
