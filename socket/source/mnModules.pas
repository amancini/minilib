﻿unit mnModules;
{$M+}{$H+}
{$IFDEF FPC}{$MODE delphi}{$ENDIF}
{**
 *  This file is part of the "Mini Library"
 *
 * @license   modifiedLGPL (modified of http://www.gnu.org/licenses/lgpl.html)
 *            See the file COPYING.MLGPL, included in this distribution,
 * @author    Zaher Dirkey <zaher, zaherdirkey>
 *
 *  https://www.w3.org/Protocols/rfc2616/rfc2616-sec5.html
 *
 *
 }
 {
           userinfo       host      port
          ┌──┴───┐ ┌──────┴──────┐ ┌┴┐
  https://john.doe@www.example.com:123/forum/questions/?tag=networking&order=newest#top
  └─┬─┘   └───────────┬──────────────┘└───────┬───────┘ └───────────┬─────────────┘ └┬┘
  scheme          authority                  path                 query           fragment

  https://en.wikipedia.org/wiki/Uniform_Resource_Identifier

  REST tools
  https://resttesttest.com
  https://httpbin.org
  http://dummy.restapiexample.com/

 }

interface

uses
  SysUtils, Classes, StrUtils, Types,
  mnClasses, mnStreams, mnFields, mnConfigs,
  mnSockets, mnConnections, mnServers;

const
  cDefaultKeepAliveTimeOut = 5000; //TODO move module

type
  TmodModuleException = class(Exception);

  TmodModuleConnection = class;
  TmodModuleConnectionClass = class of TmodModuleConnection;

  TmodCommand = class;

  { TmnHeaderField }

  TmnHeaderField = class(TmnParam)
    function GetFullString: String; override;
  end;

  { TmnHeader }

  TmnHeader = class(TmnParams)
  protected
    function CreateField: TmnField; override;
  public
    constructor Create;
  end;

  TmodRequestInfo = record
    Method: string;
    URI: utf8string;
    Protcol: string;

    Path: UTF8String;
    Module: string;
    Command: string;

    Raw: string; //Full of first line of header

    Client: string;
  end;

  { TmodRequest }

  TmodRequest = class(TObject)
  private
    FHeader: TmnHeader;
    procedure SetRequestHeader(AValue: TmnHeader);
  protected
    Info: TmodRequestInfo;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure ParsePath(URI: string; URIQuery: TmnParams = nil);
    property Method: string read Info.Method write Info.Method;
    property URI: utf8string read Info.URI write Info.URI;
    property Protcol: string read Info.Protcol write Info.Protcol;
    property Path: UTF8String read Info.Path write Info.Path;
    property Module: string read Info.Module write Info.Module;
    property Command: string read Info.Command write Info.Command;
    property Raw: string read Info.Raw write Info.Raw;
    property Client: string read Info.Client write Info.Client;

    property Header: TmnHeader read FHeader write SetRequestHeader;
  end;

  { TmodRespond }

  TmodRespond = class(TObject)
  private
    FHeader: TmnHeader;
  public
    constructor Create;
    destructor Destroy; override;
    property Header: TmnHeader read FHeader;
  end;

  TmodModule = class;

  {
    Params: (info like remoteip)
    InHeader:
    OutHeader:

    Result: Success or error and message of error
  }

  TmodCommandState = (
    cmdsRespondSent, //reposnd line, first line before header
    cmdsHeaderSent,
    cmdsContentsSent,
    cmdsEnd
  );

  TmodCommandStates = set of TmodCommandState;

  TmodeResult = (
    erSuccess,
    erKeepAlive //keep the stream connection alive, not the command
  );

  TmodeResults = set of TmodeResult;

  TmodExecuteResults = record
    Status: TmodeResults;
    Timout: Integer;
  end;

  { TmodCommand }

  TmodCommand = class(TmnObject)
  private
    FModule: TmodModule;
    FRespond: TmodRespond;
    FRequest: TmodRequest;
    FRaiseExceptions: Boolean;
    FRequestStream: TmnBufferStream;
    FRespondStream: TmnBufferStream;
    FContentSize: Int64;

    FStates: TmodCommandStates;
    procedure SetModule(const Value: TmodModule); virtual;
    function GetActive: Boolean;
  protected
    procedure Prepare(var Result: TmodExecuteResults); virtual;
    procedure RespondError(ErrorNumber: Integer; ErrorMessage: string); virtual;
    procedure RespondResult(var Result: TmodExecuteResults); virtual;
    function Execute: TmodExecuteResults; virtual;
    procedure Unprepare(var Result: TmodExecuteResults); virtual; //Shutdown it;

    property RequestStream: TmnBufferStream read FRequestStream;
    property RespondStream: TmnBufferStream read FRespondStream;
    procedure SendRespond(ALine: string); virtual;
    //Add new header, can dublicate
    procedure PostHeader(AName, AValue: string); virtual;
    //Update header by name
    procedure SetHeader(AName, AValue: string); virtual;
    //Update header by name but adding new value to old value
    procedure PutHeader(AName, AValue: string); virtual;
    procedure SendHeader; virtual;

    procedure Log(S: string); virtual;
  public
    constructor Create(AModule: TmodModule; ARequest: TmodRequest; RequestStream: TmnBufferStream = nil; RespondStream: TmnBufferStream = nil); virtual;
    destructor Destroy; override;

    property Active: Boolean read GetActive;
    //GetCommandName: make name for command when register it, useful when log the name of it
    property Module: TmodModule read FModule write SetModule;
    //Lock the server listener when execute the command
    //Prepare called after created in lucking mode
    property ContentSize: Int64 read FContentSize write FContentSize; //todo
    property RaiseExceptions: Boolean read FRaiseExceptions write FRaiseExceptions default False;
    property States: TmodCommandStates read FStates;
    property Request: TmodRequest read FRequest;
    property Respond: TmodRespond read FRespond;
  end;

  TmodCommandClass = class of TmodCommand;

  TmodCommandClassItem = class(TmnNamedObject)
  private
    FCommandClass: TmodCommandClass;
  public
    property CommandClass: TmodCommandClass read FCommandClass;
  end;

  { TmodCommandClasses }

  TmodCommandClasses = class(TmnNamedObjectList<TmodCommandClassItem>)
  private
  public
    function Add(const Name: string; CommandClass: TmodCommandClass): Integer;
  end;

  {
    Module will do simple protocol before execute command
    Module have protocol name must match when parse request, before selecting
  }

  TmodModules = class;

  { TmodModule }

  TmodModule = class(TmnNamedObject)
  private
    FAliasName: string;
    FCommands: TmodCommandClasses;
    FKeepAliveTimeOut: Integer;
    FModules: TmodModules;
    FParams: TStringList;
    FProtcols: TArray<string>;
    FUseKeepAlive: Boolean;
    FCompressing: Boolean;
    procedure SetAliasName(AValue: string);
  protected
    FFallbackCommand: TmodCommandClass;
    //Name here will corrected with registered item name for example Get -> GET
    function GetActive: Boolean; virtual;
    function GetCommandClass(var CommandName: string): TmodCommandClass; virtual;
    procedure Created; override;
    procedure DoCreateCommands; virtual;
    procedure CreateCommands;

    procedure SendHeader(ACommand: TmodCommand); virtual;

    function CreateCommand(CommandName: string; ARequest: TmodRequest; ARequestStream: TmnBufferStream = nil; ARespondStream: TmnBufferStream = nil): TmodCommand; overload;

    procedure ParseHeader(RequestHeader: TmnParams; Stream: TmnBufferStream); virtual;
    function RequestCommand(ARequest: TmodRequest; ARequestStream, ARespondStream: TmnBufferStream): TmodCommand; virtual;
    function Match(const ARequest: TmodRequest): Boolean; virtual;
    procedure Log(S: string); virtual;
    procedure Start; virtual;
    procedure Stop; virtual;
    procedure Reload; virtual;
    procedure Init; virtual;
    procedure Idle; virtual;
  public
    constructor Create(const AName, AAliasName: string; AProtcols: TArray<string>; AModules: TmodModules); virtual;
    destructor Destroy; override;
    function Execute(ARequest: TmodRequest; ARequestStream: TmnBufferStream = nil; ARespondStream: TmnBufferStream = nil): TmodExecuteResults;
    procedure ExecuteCommand(CommandName: string; ARequestStream: TmnBufferStream = nil; ARespondStream: TmnBufferStream = nil; RequestString: TArray<String> = nil);
    function RegisterCommand(vName: string; CommandClass: TmodCommandClass; AFallback: Boolean = False): Integer; overload;

    property Commands: TmodCommandClasses read FCommands;
    property Active: Boolean read GetActive;
    property Params: TStringList read FParams;
    property Modules: TmodModules read FModules;
    property Protcols: TArray<string> read FProtcols;
    property KeepAliveTimeOut: Integer read FKeepAliveTimeOut write FKeepAliveTimeOut;
    property UseKeepAlive: Boolean read FUseKeepAlive write FUseKeepAlive default False;
    property Compressing: Boolean read FCompressing write FCompressing;
    property AliasName: string read FAliasName write SetAliasName;
  end;

  TmodModuleServer = class;

  { TmodModules }

  TmodModules = class(TmnNamedObjectList<TmodModule>)
  private
    FEOFOnError: Boolean;
    FActive: Boolean;
    FEndOfLine: string;
    FDefaultModule: TmodModule;
    FDefaultProtocol: string;
    FInit: Boolean;
    FServer: TmodModuleServer;
    procedure SetEndOfLine(AValue: string);
  protected
    function GetActive: Boolean; virtual;
    procedure Created; override;
    procedure Start;
    procedure Stop;
    procedure Init;
    procedure Idle;
    property Server: TmodModuleServer read FServer;
  public
    constructor Create(AServer: TmodModuleServer);
    procedure ParseHead(ARequest: TmodRequest; const RequestLine: string); virtual;
    function Match(ARequest: TmodRequest): TmodModule; virtual;
    property DefaultProtocol: string read FDefaultProtocol write FDefaultProtocol;

    function Add(const Name, AliasName: string; AModule:TmodModule): Integer; overload;
    procedure Log(S: string); virtual;

    property Active: Boolean read GetActive;
    property EndOfLine: string read FEndOfLine write SetEndOfLine; //TODO move to module
    property DefaultModule: TmodModule read FDefaultModule write FDefaultModule;
  end;

//--- Server ---

  { TmodModuleConnection }

  TmodModuleConnection = class(TmnServerConnection)
  private
  protected
    procedure Process; override;
    procedure Prepare; override;
  public
    destructor Destroy; override;
  published
  end;

  { TmodModuleListener }

  TmodModuleListener = class(TmnListener)
  private
    function GetServer: TmodModuleServer;
  protected
    function DoCreateConnection(vStream: TmnConnectionStream): TmnConnection; override;
    procedure DoCreateStream(var Result: TmnConnectionStream; vSocket: TmnCustomSocket); override;
    property Server: TmodModuleServer read GetServer;
  public
  end;

  { TmodModuleServer }

  TmodModuleServer = class(TmnEventServer)
  private
    FModules: TmodModules;
  protected
    function DoCreateListener: TmnListener; override;
    procedure StreamCreated(AStream: TmnBufferStream); virtual;
    procedure DoBeforeOpen; override;
    procedure DoAfterClose; override;
    function CreateModules: TmodModules; virtual;
    procedure DoStart; override;
    procedure DoStop; override;
    procedure DoIdle(vListener: TmnListener); override;

  public
    constructor Create; virtual;
    destructor Destroy; override;
    property Modules: TmodModules read FModules;
  end;

  { TmnFieldHelper }

  TmnFieldHelper = class helper for TmnField
  public
    function Have(AValue: string; vSeperators: TSysCharSet = [';']): Boolean;
  end;

function ParseURI(Request: string; out URIPath: UTF8String; out URIQuery: UTF8String): Boolean; overload;
function ParseURI(Request: string; out URIPath: UTF8String; URIQuery: TmnParams): Boolean; overload;
procedure ParsePath(aRequest: string; out Name: string; out URIPath: UTF8String; URIQuery: TmnParams);

implementation

uses
  mnUtils;

function ParseURI(Request: string; out URIPath: UTF8String; out URIQuery: UTF8String): Boolean;
var
  I, J: Integer;
begin
  if Request <> '' then
    if Request[1] = '/' then //Not sure
      Delete(Request, 1, 1);

  I := 1;
  while (I <= Length(Request)) and (Request[I] = ' ') do
    Inc(I);
  J := I;
  while (I <= Length(Request)) and (Request[I] <> ' ') do
    Inc(I);

  URIPath := Copy(Request, J, I - J);

  if URIPath <> '' then
    if URIPath[1] = '/' then //Not sure
      Delete(URIPath, 1, 1);

  Result := URIPath <> '';

  { Find parameters }
  {belal taskeej getting params in case of params has space}
  J := Pos('?', URIPath);
  if J > 0 then
  begin
    URIQuery := Copy(Request, J + 1, Length(Request));
    URIPath := Copy(URIPath, 1, J - 1);
  end
  else
  begin
    URIQuery := '';
  end;
end;

function ParseURI(Request: string; out URIPath: UTF8String; URIQuery: TmnParams): Boolean;
var
  aParams: utf8string;
begin
  Result := ParseURI(Request, URIPath, aParams);
  if Result then
    if URIQuery <> nil then
      //ParseParams(aParams, False);
      StrToStringsCallback(aParams, URIQuery, @ParamsCallBack, ['&'], [' ']);
end;

procedure ParsePath(aRequest: string; out Name: string; out URIPath: UTF8String; URIQuery: TmnParams);
begin
  ParseURI(aRequest, URIPath, URIQuery);
  Name := SubStr(URIPath, '/', 0);
  URIPath := Copy(URIPath, Length(Name) + 1, MaxInt);
end;

{ TmodRespond }

constructor TmodRespond.Create;
begin
  inherited;
  FHeader := TmnHeader.Create;
end;

destructor TmodRespond.Destroy;
begin
  FreeAndNil(FHeader);
  inherited;
end;

{ TmodRequest }

procedure TmodRequest.SetRequestHeader(AValue: TmnHeader);
begin
  if FHeader <> AValue then
  begin
    FreeAndNil(FHeader);
    FHeader := AValue;
  end;
end;

constructor TmodRequest.Create;
begin
  inherited;
  FHeader := TmnHeader.Create;
end;

destructor TmodRequest.Destroy;
begin
  FreeAndNil(FHeader);
  inherited Destroy;
end;

procedure TmodRequest.Clear;
begin
  Initialize(Info);
end;

procedure TmodRequest.ParsePath(URI: string; URIQuery: TmnParams);
begin
  mnModules.ParsePath(Self.URI, Self.Info.Module, Self.Info.Path, URIQuery);
end;

{ TmnHeaderField }

function TmnHeaderField.GetFullString: String;
begin
  Result := GetNameValue(': ');
end;

{ TmnHeader }

constructor TmnHeader.Create;
begin
  inherited Create;
  AutoRemove := True;
end;

function TmnHeader.CreateField: TmnField;
begin
  Result := TmnHeaderField.Create;
end;

{ TmodModuleListener }

constructor TmodModuleServer.Create;
begin
  inherited;
  FModules := CreateModules;
  Port := '81';
end;

function TmodModuleServer.CreateModules: TmodModules;
begin
  Result := TmodModules.Create(Self)
end;

destructor TmodModuleServer.Destroy;
begin
  FreeAndNil(FModules);
  inherited;
end;

destructor TmodModuleConnection.Destroy;
begin
  inherited;
end;

{ TmodModuleConnection }

procedure TmodModuleConnection.Prepare;
begin
  inherited;
  (Listener.Server as TmodModuleServer).Modules.Init;
end;

procedure TmodModuleConnection.Process;
var
  aRequestLine: string;
  aRequest: TmodRequest;
  aModule: TmodModule;
  Result: TmodExecuteResults;
begin
  inherited;
  aRequestLine := TrimRight(Stream.ReadLineUTF8);
  if Connected and (aRequestLine <> '') then //aRequestLine empty when timeout but not disconnected
  begin
    aRequest := TmodRequest.Create;
    try
      (Listener.Server as TmodModuleServer).Modules.ParseHead(aRequest, aRequestLine);
      aModule := (Listener.Server as TmodModuleServer).Modules.Match(aRequest);
      if (aModule = nil) and ((Listener.Server as TmodModuleServer).Modules.Count > 0) then
        aModule := (Listener.Server as TmodModuleServer).Modules.DefaultModule; //fall back

      if (aModule = nil) then
      begin
        Stream.Disconnect; //if failed
      end
      else
      try
        if aModule <> nil then
        begin
          aRequest.Client := RemoteIP;
          Result := aModule.Execute(aRequest, Stream, Stream);
        end;
      finally
      end;
    finally
      FreeAndNil(aRequest); //if create command then aRequest change to nil
    end;

    if Stream.Connected then
    begin
      if (erKeepAlive in Result.Status) then
        Stream.ReadTimeout := Result.Timout
      else
        Stream.Disconnect;
    end;
  end;
end;

function TmodModuleServer.DoCreateListener: TmnListener;
begin
  Result := TmodModuleListener.Create;
end;

procedure TmodModuleServer.DoIdle(vListener: TmnListener);
begin
  inherited;
  Modules.Idle;
end;

procedure TmodModuleServer.DoStart;
begin
  inherited;
  Modules.Start;
end;

procedure TmodModuleServer.DoStop;
begin
  if Modules<>nil then
    Modules.Stop;
  inherited;
end;

procedure TmodModuleServer.StreamCreated(AStream: TmnBufferStream);
begin
  AStream.EndOfLine := Modules.EndOfLine;
  //AStream.EOFOnError := Modules.EOFOnError;
end;

procedure TmodModuleServer.DoBeforeOpen;
begin
  inherited;
end;

procedure TmodModuleServer.DoAfterClose;
begin
  inherited;
end;

{ TmodCustomCommandListener }

function TmodModuleListener.DoCreateConnection(vStream: TmnConnectionStream): TmnConnection;
begin
  Result := TmodModuleConnection.Create(Self, vStream);
end;

procedure TmodModuleListener.DoCreateStream(var Result: TmnConnectionStream; vSocket: TmnCustomSocket);
begin
  inherited;
  Result.ReadTimeout := -1;
  Server.StreamCreated(Result);
end;

function TmodModuleListener.GetServer: TmodModuleServer;
begin
  Result := inherited Server as TmodModuleServer;
end;

{ TmodCommand }

constructor TmodCommand.Create(AModule: TmodModule; ARequest: TmodRequest; RequestStream: TmnBufferStream; RespondStream: TmnBufferStream);
begin
  inherited Create;
  FModule := AModule;
  FRequestStream := RequestStream; //do not free
  FRespondStream := RespondStream; //do not free
  FRequest := ARequest; //do not free
  FRespond := TmodRespond.Create;
end;

destructor TmodCommand.Destroy;
begin
  FreeAndNil(FRespond);
  inherited;
end;

procedure TmodCommand.Prepare(var Result: TmodExecuteResults);
begin
end;

procedure TmodCommand.SendHeader;
begin
  if not (cmdsRespondSent in FStates) then
    raise TmodModuleException.Create('Respond line not sent');
  if cmdsHeaderSent in FStates then
    raise TmodModuleException.Create('Header is sent');
  FStates := FStates + [cmdsHeaderSent];
  Module.SendHeader(Self);
end;

procedure TmodCommand.Log(S: string);
begin
  Module.Log(S);
end;

procedure TmodCommand.RespondResult(var Result: TmodExecuteResults);
begin
end;

procedure TmodCommand.RespondError(ErrorNumber: Integer; ErrorMessage: string);
begin
end;

procedure TmodCommand.Unprepare(var Result: TmodExecuteResults);
begin
end;

procedure TmodCommand.SendRespond(ALine: string);
begin
  if cmdsRespondSent in FStates then
    raise TmodModuleException.Create('Respond is sent');
  RespondStream.WriteLineUTF8(ALine);
  FStates := FStates + [cmdsRespondSent];
end;

procedure TmodCommand.PostHeader(AName, AValue: string);
begin
  if cmdsHeaderSent in FStates then
    raise TmodModuleException.Create('Header is sent');
  Respond.Header.Add(AName, AValue);
end;

function TmodCommand.Execute: TmodExecuteResults;
begin
  Result.Status := []; //default to be not keep alive, not sure, TODO
  Prepare(Result);
  RespondResult(Result);
  Unprepare(Result);
end;

function TmodCommand.GetActive: Boolean;
begin
  Result := (Module <> nil) and (Module.Active);
end;

procedure TmodCommand.PutHeader(AName, AValue: string);
begin
  if cmdsHeaderSent in FStates then
    raise TmodModuleException.Create('Header is sent');
  Respond.Header.Put(AName, AValue);
end;

procedure TmodCommand.SetHeader(AName, AValue: string);
begin
  if cmdsHeaderSent in FStates then
    raise TmodModuleException.Create('Header is sent');
  Respond.Header.Put(AName, AValue);
end;

procedure TmodCommand.SetModule(const Value: TmodModule);
begin
  FModule := Value;
end;

function TmodCommandClasses.Add(const Name: string; CommandClass: TmodCommandClass): Integer;
var
  aItem: TmodCommandClassItem;
begin
  aItem := TmodCommandClassItem.Create;
  aItem.Name := UpperCase(Name);
  aItem.FCommandClass := CommandClass;
  Result := inherited Add(aItem);
end;

{ TmodModule }

function TmodModule.CreateCommand(CommandName: string; ARequest: TmodRequest; ARequestStream: TmnBufferStream; ARespondStream: TmnBufferStream): TmodCommand;
var
//  aName: string;
  aClass: TmodCommandClass;
begin
  //aName := GetCommandName(ARequest, ARequestStream);

  aClass := GetCommandClass(CommandName);
  if aClass <> nil then
  begin
    Result := aClass.Create(Self, ARequest, ARequestStream, ARespondStream);
  end
  else
    Result := nil;
end;

function TmodModule.GetCommandClass(var CommandName: string): TmodCommandClass;
var
  aItem: TmodCommandClassItem;
begin
  aItem := Commands.Find(CommandName);
  if aItem <> nil then
  begin
    CommandName := aItem.Name;
    Result := aItem.CommandClass;
  end
  else
    Result := FFallbackCommand;
end;

procedure TmodModule.Idle;
begin

end;

procedure TmodModule.Init;
begin

end;

procedure TmodModule.ParseHeader(RequestHeader: TmnParams; Stream: TmnBufferStream);
var
  line: string;
begin
  if Stream <> nil then
  begin
    while not (cloRead in Stream.Done) do
    begin
      line := Stream.ReadLineUTF8;
      if line = '' then
        break
      else
      begin
        RequestHeader.AddItem(line, ':', true);
      end;
    end;
  end;
end;

procedure TmodModule.Created;
begin
  inherited;
end;

procedure TmodModule.CreateCommands;
begin
  if Commands.Count = 0 then
    DoCreateCommands;
end;

procedure TmodModule.SendHeader(ACommand: TmodCommand);
var
  item: TmnField;
  s: string;
begin
  for item in ACommand.Respond.Header do
  begin
    s := item.GetNameValue(': ');
    //WriteLn(s);
    ACommand.RespondStream.WriteLineUTF8(S);
  end;
  ACommand.RespondStream.WriteLineUTF8(UTF8String(''));
end;

procedure TmodModule.Start;
begin

end;

procedure TmodModule.Stop;
begin

end;

function TmodModule.RequestCommand(ARequest: TmodRequest; ARequestStream, ARespondStream: TmnBufferStream): TmodCommand;
begin
  Result := CreateCommand(ARequest.Command, ARequest, ARequestStream, ARespondStream);
end;

constructor TmodModule.Create(const AName, AAliasName: string; AProtcols: TArray<string>; AModules: TmodModules);
begin
  inherited Create;
  Name := AName;
  FAliasName := AAliasName;
  FProtcols := AProtcols;
  FModules := AModules;
  FModules.Add(Self);
  FParams := TStringList.Create;
  FCommands := TmodCommandClasses.Create(True);
  FKeepAliveTimeOut := cDefaultKeepAliveTimeOut; //TODO move module
end;

destructor TmodModule.Destroy;
begin
  FreeAndNil(FParams);
  FreeAndNil(FCommands);
  inherited;
end;

procedure TmodModule.DoCreateCommands;
begin
end;

function TmodModule.Match(const ARequest: TmodRequest): Boolean;
begin
  Result := SameText(AliasName, ARequest.Module) and ((Protcols = nil) or StrInArray(ARequest.Protcol, Protcols));
end;

procedure TmodModule.Log(S: string);
begin
end;

function TmodModule.Execute(ARequest: TmodRequest; ARequestStream: TmnBufferStream; ARespondStream: TmnBufferStream): TmodExecuteResults;
var
  aCMD: TmodCommand;
begin
  CreateCommands;

  Result.Status := [erSuccess];

  ParseHeader(ARequest.Header, ARequestStream);

  aCmd := RequestCommand(ARequest, ARequestStream, ARespondStream);

  if aCMD <> nil then
  begin
    try
      try
        Result := aCMD.Execute;
        Result.Status := Result.Status + [erSuccess];
      except
        on E: Exception do
          aCMD.RespondError(500, E.Message);
      end;
    finally
      FreeAndNil(aCMD);
    end;
  end
  else
    raise TmodModuleException.Create('Can not find command or fallback command: ' + ARequest.Command);
end;

procedure TmodModule.ExecuteCommand(CommandName: string; ARequestStream: TmnBufferStream; ARespondStream: TmnBufferStream; RequestString: TArray<String>);
var
  ARequest: TmodRequest;
begin
  ARequest.Command := CommandName;
  Execute(ARequest, ARequestStream, ARespondStream);
end;

procedure TmodModule.SetAliasName(AValue: string);
begin
  if FAliasName =AValue then
    Exit;
  FAliasName := AValue;
end;

function TmodModule.GetActive: Boolean;
begin
  Result := Modules.Active; //todo
end;

function TmodModule.RegisterCommand(vName: string; CommandClass: TmodCommandClass; AFallback: Boolean): Integer;
begin
{  if Active then
    raise TmodModuleException.Create('Server is Active');}
  if FCommands.Find(vName) <> nil then
    raise TmodModuleException.Create('Command already exists: ' + vName);
  Result := FCommands.Add(vName, CommandClass);
  if AFallback then
    FFallbackCommand := CommandClass;
end;

procedure TmodModule.Reload;
begin

end;

{ TmodModules }

function TmodModules.Add(const Name, AliasName: string; AModule: TmodModule): Integer;
begin
  AModule.Name := Name;
  AModule.AliasName := AliasName;
  Result := inherited Add(AModule);
end;

procedure TmodModules.SetEndOfLine(AValue: string);
begin
  if FEndOfLine =AValue then
    Exit;
{  if Active then
    raise TmodModuleException.Create('You can''t change EOL while server is active');}
  FEndOfLine :=AValue;
end;

procedure TmodModules.Start;
var
  aModule: TmodModule;
begin
  for aModule in Self do
    aModule.Start;
  FActive := True;
end;

procedure TmodModules.Stop;
var
  aModule: TmodModule;
begin
  FActive := False;
  for aModule in Self do
    aModule.Stop;
end;

function TmodModules.GetActive: Boolean;
begin
  Result := FActive;
end;

procedure TmodModules.Idle;
var
  aModule: TmodModule;
begin
  for aModule in Self do
    aModule.Idle;
end;

procedure TmodModules.Init;
var
  aModule: TmodModule;
begin
  if not FInit then
  begin
    FInit := True;
    for aModule in Self do
      aModule.Init;
  end;
end;

procedure TmodModules.Log(S: string);
begin
  Server.Listener.Log(S);
end;

constructor TmodModules.Create(AServer: TmodModuleServer);
begin
  inherited Create;
  FServer := AServer;
end;

procedure TmodModules.Created;
begin
  inherited;
  FEOFOnError := True;
  FEndOfLine := sWinEndOfLine; //for http protocol
end;

procedure TmodModules.ParseHead(ARequest: TmodRequest; const RequestLine: string);
var
  aRequests: TStringList;
begin
  ARequest.Clear;

  aRequests := TStringList.Create;
  try
    StrToStrings(RequestLine, aRequests, [' '], []);
    if aRequests.Count > 0 then
      ARequest.Method := aRequests[0];
    if aRequests.Count > 1 then
      ARequest.URI := aRequests[1];
    if aRequests.Count > 2 then
      ARequest.Protcol := aRequests[2];
  finally
    FreeAndNil(aRequests);
  end;
  if ARequest.Protcol = '' then
    ARequest.Protcol := DefaultProtocol;

  ARequest.Raw := RequestLine;
  ARequest.ParsePath(ARequest.URI);
end;

function TmodModules.Match(ARequest: TmodRequest): TmodModule;
var
  item: TmodModule;
begin
  Result := nil;
  for item in Self do
  begin
    if item.Match(ARequest) then
    begin
      Result := item;
      break;
    end;
  end;
end;

{ TmnFieldHelper }

function TmnFieldHelper.Have(AValue: string; vSeperators: TSysCharSet): Boolean;
var
  SubValues : TStringList;
begin
  if Self = nil then
    Result := false
  else
  begin
    SubValues := TStringList.Create;
    try
      StrToStrings(AsString, SubValues, vSeperators, [' ']);
      Result := SubValues.IndexOf(AValue) >=0;
    finally
      SubValues.Free;
    end;
  end;
end;

end.
