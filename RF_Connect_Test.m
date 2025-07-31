
%% RF_Connect_Test.m
% Standalone script to test RealFlight SOAP control and telemetry from MATLAB.
%
% - Sends manual control channel values (Ail, Ele, Thr, Rud)
% - Receives and prints telemetry (airspeed, altitude, status)
% - Does not use the GUI
%
% Usage:
%   1. Make sure RealFlight is running with controller input unlocked
%   2. Run this script in MATLAB to test SOAP connection

% Created By: Islam Elnady... islamelnady@yahoo.com

rfUrl = 'http://127.0.0.1:18083';  % SOAP endpoint
channels = [0.5, 0.48, 1.0, 0.5];   % [roll, pitch, throttle, yaw]
selectedChannelsMask = 2^numel(channels) - 1;

%% Function: Send SOAP Request and Extract Response
function response = sendSoapRequest(url, action, body)
    import matlab.net.*
    import matlab.net.http.*
    header = [
        HeaderField('Content-Type', 'text/xml;charset=UTF-8'), ...
        HeaderField('SOAPAction', action)
    ];
    request = RequestMessage('POST', header, char(body));
    try
        reply = send(request, URI(url));
        % Handle string, char, or XML DOM
        if isa(reply.Body.Data, 'string') || isa(reply.Body.Data, 'char')
            response = char(reply.Body.Data);
        elseif isa(reply.Body.Data, 'org.w3c.dom.Document')
            % Convert Java XML DOM to string
            xmlObj = reply.Body.Data;
            transformer = javax.xml.transform.TransformerFactory.newInstance().newTransformer();
            source = javax.xml.transform.dom.DOMSource(xmlObj);
            stringWriter = java.io.StringWriter();
            result = javax.xml.transform.stream.StreamResult(stringWriter);
            transformer.transform(source, result);
            response = char(stringWriter.toString());
        else
            response = '';
        end
    catch e
        disp(['[SOAP Error] ', e.message]);
        response = '';
    end
end

%% Step 1: Restore Original Controller (recommended)
disp('[INFO] Restoring RealFlight controller...');
restoreXML = [
    '<?xml version="1.0"?>' ...
    '<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">' ...
    '<soap:Body>' ...
    '<RestoreOriginalControllerDevice><a>1</a><b>2</b></RestoreOriginalControllerDevice>' ...
    '</soap:Body></soap:Envelope>'
];
sendSoapRequest(rfUrl, 'RestoreOriginalControllerDevice', restoreXML);
pause(1);

%% Step 2: Inject UAV External Controller
disp('[INFO] Injecting external controller interface...');
injectXML = [
    '<?xml version="1.0"?>' ...
    '<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">' ...
    '<soap:Body>' ...
    '<InjectUAVControllerInterface><a>1</a><b>2</b></InjectUAVControllerInterface>' ...
    '</soap:Body></soap:Envelope>'
];
sendSoapRequest(rfUrl, 'InjectUAVControllerInterface', injectXML);
pause(1);

%% Step 3: Main Control and Telemetry Loop
disp('[INFO] Starting control + telemetry loop...');
t0 = tic;
while 1  % run for 5 seconds
    t = toc(t0);
    channels(3) = min(1.0, 0.3 + 0.2 * t);  % throttle ramp

    % Format channel values as XML <item>...</item>
    items = join(arrayfun(@(v) sprintf('<item>%.4f</item>', v), ...
        channels, 'UniformOutput', false), '');

    % Build ExchangeData SOAP request
    exchangeXML = [
        '<?xml version="1.0"?>' ...
        '<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">' ...
        '<soap:Body>' ...
        '<ExchangeData><pControlInputs>' ...
        sprintf('<m-selectedChannels>%d</m-selectedChannels>', selectedChannelsMask) ...
        '<m-channelValues-0to1>' items '</m-channelValues-0to1>' ...
        '</pControlInputs></ExchangeData>' ...
        '</soap:Body></soap:Envelope>'
    ];

    % Send and receive telemetry
    response = sendSoapRequest(rfUrl, 'ExchangeData', exchangeXML);

    % --- Parse and display telemetry if available
    if isempty(response)
        disp('[!] No response from RealFlight.');
    else
        airspeed = regexp(response, '<m-airspeed-MPS>([^<]+)</m-airspeed-MPS>', 'tokens', 'once');
        altitude = regexp(response, '<m-altitudeASL-MTR>([^<]+)</m-altitudeASL-MTR>', 'tokens', 'once');
        status   = regexp(response, '<m-currentAircraftStatus>([^<]+)</m-currentAircraftStatus>', 'tokens', 'once');
        if ~isempty(airspeed) && ~isempty(altitude)
            fprintf('Airspeed: %.2f m/s | Altitude ASL: %.2f m | Status: %s\n', ...
                str2double(airspeed{1}), str2double(altitude{1}), status{1});
        else
            disp('[!] Telemetry fields not found. Waiting for aircraft to activate...');
        end
    end

    pause(0.05);  % 20 Hz loop
end

disp('[INFO] Control loop complete.');






