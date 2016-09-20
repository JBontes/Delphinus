{
#########################################################
# Copyright by Alexander Benikowski                     #
# This unit is part of the Delphinus project hosted on  #
# https://github.com/Memnarch/Delphinus                 #
#########################################################
}
unit DN.Compiler.MSBuild;

interface

uses
  Windows,
  Classes,
  SysUtils,
  DN.Types,
  DN.Compiler.Intf,
  DN.Compiler,
  DN.Compiler.ValueOverrides.Intf,
  DN.VariableResolver.Compiler.Factory;

type
  TDNMSBuildCompiler = class(TDNCompiler)
  private
    FEmbarcaderoBinFolder: string;
    FLogFile: string;
    FVersion: TCompilerVersion;
    function BuildCommandLine(const AProjectfile: string): string;
    function GetMSBuildProperties: string;
    function Execute(const ACommandLine: string): Cardinal;
    function BuildParameterOverrideString(const ADefaultOverrides: ICompilerValueOverrides): string;
    function GetParameterOverrides(AConfig: TDNCompilerConfig): string;
  protected
    function GetVersion: TCompilerVersion; override;
  public
    constructor Create(const AVariableResolverFactory: TDNCompilerVariableResolverFacory;
      const AEmbarcaderoBinFolder: string);
    function Compile(const AProjectFile: string): Boolean; override;
  end;

implementation

uses
  IOUtils,
  ShellApi,
  DN.Utils,
  DN.VariableResolver.Intf,
  DN.Compiler.ValueOverrides.Factory;

{ TDNMSBuildCompiler }

function TDNMSBuildCompiler.BuildCommandLine(
  const AProjectfile: string): string;
begin
  Result := 'call "' + FEmbarcaderoBinFolder + '\RSVars.bat"';
  Result := Result + '& msbuild "' + AProjectfile + '" ' + GetMSBuildProperties() + ' > "' + FLogFile + '"';
  Result := 'cmd.exe /c ' + Result;
end;

function TDNMSBuildCompiler.BuildParameterOverrideString(
  const ADefaultOverrides: ICompilerValueOverrides): string;
const
  CParameterOverrides = '/p:%s=%s';
  CDebugInformation = 'DCC_DebugInformation';
var
  LParameter, LValue: string;
begin
  if not FParameterOverrides.ContainsKey(CDebugInformation) then
    Result := Format(CParameterOverrides, [CDebugInformation, ADefaultOverrides.DebugInformation])
  else
    Result := '';

  for LParameter in FParameterOverrides.Keys do
  begin
    LValue := FParameterOverrides[LParameter];
    if LValue = '' then
      LValue := '""';
    Result := Result + ' ' + Format(CParameterOverrides, [LParameter, LValue]);
  end;
end;

function TDNMSBuildCompiler.Compile(const AProjectFile: string): Boolean;
begin
  Result := Execute(BuildCommandLine(AProjectFile)) = 0;
end;

constructor TDNMSBuildCompiler.Create(const AVariableResolverFactory: TDNCompilerVariableResolverFacory;
  const AEmbarcaderoBinFolder: string);
begin
  inherited Create(AVariableResolverFactory);
  FEmbarcaderoBinFolder := AEmbarcaderoBinFolder;
  FLogFile := TPath.GetTempFileName();
end;

function TDNMSBuildCompiler.Execute(const ACommandLine: string): Cardinal;
var
  LExecInfo: TShellExecuteInfo;
begin
  Result := MaxInt;
  LExecInfo.cbSize := sizeof(TShellExecuteInfo);
  LExecInfo.fMask := SEE_MASK_NOCLOSEPROCESS;
  LExecInfo.Wnd := 0;
  LExecInfo.lpVerb := nil;
  LExecInfo.lpFile := 'cmd.exe';
  LExecInfo.lpParameters := PChar(ACommandLine);
  LExecInfo.lpDirectory := nil;
  LExecInfo.nShow := SW_HIDE;
  LExecInfo.hInstApp := 0;

  ShellExecuteEx(@LExecInfo);
  WaitForSingleObject(LExecInfo.hProcess,INFINITE);
  GetExitCodeProcess(LExecInfo.hProcess, Result);
  CloseHandle(LExecInfo.hProcess);

  if TFile.Exists(FLogFile) then
  begin
    Log.LoadFromFile(FLogFile);
    TFile.Delete(FLogFile);
  end;
end;

function TDNMSBuildCompiler.GetMSBuildProperties: string;
var
  LResolver: IVariableResolver;
begin
  Result := '/target:' + TDNCompilerTargetName[Target];
  Result := Result + ' /p:config=' + TDNCompilerConfigName[Config];
  Result := Result + ' /P:platform=' + TDNCompilerPlatformName[Platform];

  LResolver := CreateResolver();

  if DCUOutput <> '' then
    Result := Result + ' /p:DCC_DcuOutput="' + LResolver.Resolve(ExcludeTrailingPathDelimiter(DCUOutput)) + '"';

  if DCPOutput <> '' then
    Result := Result + ' /p:DCC_DcpOutput="' + LResolver.Resolve(ExcludeTrailingPathDelimiter(DCPOutput)) + '"';

  if EXEOutput <> '' then
    Result := Result + ' /p:DCC_ExeOutput="' + LResolver.Resolve(ExcludeTrailingPathDelimiter(ExeOutput)) + '"';

  if BPLOutput <> '' then
    Result := Result + ' /p:DCC_BplOutput="' + LResolver.Resolve(ExcludeTrailingPathDelimiter(BPLOutput)) + '"';

  Result := Result + ' ' + GetParameterOverrides(Config);
end;

function TDNMSBuildCompiler.GetParameterOverrides(
  AConfig: TDNCompilerConfig): string;
begin
  Result := BuildParameterOverrideString(TValueOverridesFactory.CreateOverride(AConfig, Version));
end;

function TDNMSBuildCompiler.GetVersion: TCompilerVersion;
var
  LPos: Integer;
  LValue: string;
  LSettings: TFormatSettings;
const
  CWin32Compiler = 'dcc32.exe';
  CCommandLine = 'cmd.exe /c ""%s" --version > "%s""';
begin
  if FVersion = 0 then
  begin
    FVersion := -1;
    if Execute(Format(CCommandLine, [TPath.Combine(FEmbarcaderoBinFolder, CWin32Compiler), FLogFile])) = 0 then
    begin
      if (Log.Count > 0) then
      begin
        LPos := Pos(') ', Log[0]);
        if LPos > 1 then
        begin
          LValue := Copy(Log[0], LPos + 2, Length(Log[0]));
          LSettings := TFormatSettings.Create();
          LSettings.DecimalSeparator := '.';
          FVersion := StrToFloatDef(LValue, -1, LSettings);
        end;
      end;
    end;
  end;
  Result := FVersion;
end;

end.
