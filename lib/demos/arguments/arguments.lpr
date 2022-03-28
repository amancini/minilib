program arguments;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, CustApp, mnParams, mnUtils;

type

  { TMyArguments }

  TMyArguments = class(TCustomApplication)
  protected
    procedure DoRun; override;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
    procedure WriteHelp; virtual;
  end;

procedure MyArgumentsCallbackProc(Sender: Pointer; Index:Integer; Name, Value: string; IsSwitch:Boolean; var Resume: Boolean);
begin
  Writeln(Name + '=' + Value);
end;

{ TMyArguments }

procedure TMyArguments.DoRun;
var
  ErrorMsg: String;
  sText: string;
begin
  // quick check parameters
  ErrorMsg :=CheckOptions('h', 'help');
  if ErrorMsg <>'' then begin
    ShowException(Exception.Create(ErrorMsg));
    Terminate;
    Exit;
  end;

  // parse parameters
  if HasOption('h', 'help') then begin
    WriteHelp;
    Terminate;
    Exit;
  end;

  //sText := '-t -s -v: value test';
  sText := 'build c:\projects\project.pro -t /s -v: " -z -d -r: value" test --value:testin --verbose=true platform=win32 compiler=dccarm -x=-x';
  //sText := '"-v":test'; //bug
  ParseArgumentsCallback(sText, @MyArgumentsCallbackProc, nil, ['-', '/'], [' ', #9], ['''','"'], [':', '=']);

  ReadLn();

  // stop program loop
  Terminate;
end;

constructor TMyArguments.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);
  StopOnException :=True;
end;

destructor TMyArguments.Destroy;
begin
  inherited Destroy;
end;

procedure TMyArguments.WriteHelp;
begin
  { add your help code here }
  writeln('Usage: ', ExeName, ' -h');
end;

var
  Application: TMyArguments;
begin
  Application :=TMyArguments.Create(nil);
  Application.Title :='Arguments';
  Application.Run;
  Application.Free;
end.
