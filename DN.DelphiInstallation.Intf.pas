unit DN.DelphiInstallation.Intf;

interface

uses
  Graphics;

type
  IDNDelphiInstallation = interface
    ['{B460C736-86F8-49DE-AD72-53BB6D8D71D6}']
    function GetIcon: TIcon;
    function GetName: string;
    function GetRoot: string;
    function GetDirectory: string;
    function GetApplication: string;
    function GetEdition: string;
    function GetBDSVersion: string;
    function GetBDSCommonDir: string;

    function IsRunning: Boolean;
    property Name: string read GetName;
    property Edition: string read GetEdition;
    property BDSVersion: string read GetBDSVersion;
    property Icon: TIcon read GetIcon;
    property Root: string read GetRoot;
    property Directory: string read GetDirectory;
    property Application: string read GetApplication;
    property BDSCommonDir: string read GetBDSCommonDir;
  end;

implementation

end.
