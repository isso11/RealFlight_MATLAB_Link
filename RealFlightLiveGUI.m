% RealFlight Live Control GUI (with sliders, aerospace artificial horizon, and buttons)
% MODIFIED: Sliders now send data live during movement.
% Created By: Islam Elnady... islamelnady@yahoo.com
function RealFlightLiveGUI()
    f = uifigure('Name','RealFlight Live Control', 'Position', [100 100 750 600]);
    
    % --- UI Elements ---
    % Sliders
    rollSlider = createSlider(f, 'Aileron', 480);
    pitchSlider = createSlider(f, 'Elevator', 420);
    throttleSlider = createSlider(f, 'Throttle', 360);
    yawSlider = createSlider(f, 'Rudder', 300);
    
    % Start/Stop toggle button
    startBtn = uibutton(f, 'Text', 'Start', 'Position', [230 230 100 40], 'FontWeight', 'bold');
    
    % Status text
    statusText = uilabel(f, 'Text', 'Status: Idle', 'Position', [200 180 250 30], 'FontSize', 10);
    
    % Built-in Artificial Horizon from Aerospace Toolbox
    horizon = uiaerohorizon(f, 'Position', [530 230 180 180]);
    
    % --- Configuration ---
    rfUrl = 'http://127.0.0.1:18083';
    isRunning = false;
    
    % --- Callbacks ---
    startBtn.ButtonPushedFcn = @(~,~) toggleLoop();
    
    % --- Core Functions ---

    % Helper function to update slider value and text box in real-time
    function updateLiveValue(sliderSrc, eventData, linkedEditBox)
        % This function is called continuously while a slider is being dragged.
        % It ensures the slider's main Value property and the linked text box
        % are updated in real-time, allowing the main loop to send live data.
        liveValue = eventData.Value;
        
        % --- KEY CHANGE ---
        % Immediately update the slider's main 'Value' property.
        % The main loop reads this property, so this makes the update live.
        sliderSrc.Value = liveValue;
        
        % Also update the linked numeric edit box.
        linkedEditBox.Value = liveValue;
    end

    % SOAP helper function
    function response = sendSoapRequest(url, action, body)
        import matlab.net.*
        import matlab.net.http.*
        header = [HeaderField('Content-Type','text/xml;charset=UTF-8'), HeaderField('SOAPAction', action)];
        request = RequestMessage('POST', header, char(body));
        try
            reply = send(request, URI(url));
            if isa(reply.Body.Data, 'char') || isa(reply.Body.Data, 'string')
                response = char(reply.Body.Data);
            elseif isa(reply.Body.Data, 'org.w3c.dom.Document')
                transformer = javax.xml.transform.TransformerFactory.newInstance().newTransformer();
                source = javax.xml.transform.dom.DOMSource(reply.Body.Data);
                writer = java.io.StringWriter();
                result = javax.xml.transform.stream.StreamResult(writer);
                transformer.transform(source, result);
                response = char(writer.toString());
            else
                response = '';
            end
        catch e
            fprintf('[SOAP Error] %s\n', e.message);
            response = '';
        end
    end

    % Function to initialize connection to RealFlight
    function setupConnection()
        statusText.Text = 'Connecting: Restoring controller...';
        drawnow;
        restore = '<?xml version="1.0"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"><soap:Body><RestoreOriginalControllerDevice><a>1</a><b>2</b></RestoreOriginalControllerDevice></soap:Body></soap:Envelope>';
        inject  = '<?xml version="1.0"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"><soap:Body><InjectUAVControllerInterface><a>1</a><b>2</b></InjectUAVControllerInterface></soap:Body></soap:Envelope>';
        sendSoapRequest(rfUrl, 'RestoreOriginalControllerDevice', restore);
        pause(0.1);
        statusText.Text = 'Connecting: Injecting interface...';
        drawnow;
        sendSoapRequest(rfUrl, 'InjectUAVControllerInterface', inject);
        pause(0.1);
    end

    % Function to create a slider with its label, text box, and reset button
    function slider = createSlider(parent, name, y)
        uilabel(parent, 'Position', [30 y 80 20], 'Text', name);
        slider = uislider(parent, 'Position', [120 y+10 160 3], 'Limits', [0 1], 'Value', 0.5);
        editBox = uieditfield(parent, 'numeric', 'Position', [290 y 50 22], 'Value', 0.5, 'Limits', [0 1]);
        resetBtn = uibutton(parent, 'Text', 'Reset', 'Position', [350 y 50 22], 'ButtonPushedFcn', @(~,~) resetControl());
        
        % --- MODIFIED BEHAVIOR ---
        % Use ValueChangingFcn for live updates. This callback now calls our
        % helper function to update the slider's own value property in real-time.
        slider.ValueChangingFcn = @(src, event) updateLiveValue(src, event, editBox);
        
        % The ValueChangedFcn is no longer needed, as ValueChangingFcn handles the final value too.
        
        % This remains the same, linking the text box back to the slider
        editBox.ValueChangedFcn = @(src,~) set(slider, 'Value', src.Value);
        
        function resetControl()
            newValue = 0.5;
            if strcmp(name, 'Throttle')
                newValue = 0.0; % Throttle resets to zero
            end
            slider.Value = newValue;
            editBox.Value = newValue;
        end
    end

    % Function to start or stop the main control loop
    function toggleLoop()
        if ~isRunning
            isRunning = true;
            startBtn.Text = 'Stop';
            loop();
        else
            isRunning = false;
            startBtn.Text = 'Start';
        end
    end

    % Main control and telemetry loop
    function loop()
        setupConnection();
        while isvalid(f) && isRunning
            % Read current values from sliders
            u = [rollSlider.Value, pitchSlider.Value, throttleSlider.Value, yawSlider.Value];
            
            % Format control inputs into XML list
            items = join(arrayfun(@(v) sprintf('<item>%.4f</item>', v), u, 'UniformOutput', false), '');
            mask = 2^numel(u) - 1;
            
            % Build SOAP ExchangeData message
            xml = [
                '<?xml version="1.0"?>' ...
                '<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"><soap:Body>' ...
                '<ExchangeData><pControlInputs>' ...
                sprintf('<m-selectedChannels>%d</m-selectedChannels>', mask) ...
                '<m-channelValues-0to1>' items '</m-channelValues-0to1>' ...
                '</pControlInputs></ExchangeData>' ...
                '</soap:Body></soap:Envelope>'
            ];
            
            % Send control data and receive telemetry
            response = sendSoapRequest(rfUrl, 'ExchangeData', xml);
            
            % Parse and display telemetry
            pitch = regexp(response, '<m-inclination-DEG>([^<]+)</m-inclination-DEG>', 'tokens', 'once');
            roll = regexp(response, '<m-roll-DEG>([^<]+)</m-roll-DEG>', 'tokens', 'once');
            airspeed = regexp(response, '<m-airspeed-MPS>([^<]+)</m-airspeed-MPS>', 'tokens', 'once');
            altitude = regexp(response, '<m-altitudeASL-MTR>([^<]+)</m-altitudeASL-MTR>', 'tokens', 'once');
            
            if ~isempty(airspeed) && ~isempty(altitude)
                statusText.Text = sprintf('Airspeed: %.1f m/s | Altitude: %.1f m', str2double(airspeed{1}), str2double(altitude{1}));
            else
                statusText.Text = 'Status: Running, waiting for telemetry...';
            end
            
            if ~isempty(pitch) && ~isempty(roll)
                horizon.Pitch = str2double(pitch{1});
                horizon.Roll = str2double(roll{1});
            end
            
            % Pause to maintain a steady update rate (~200 Hz)
            pause(0.005);
            drawnow; % Ensure UI updates are processed
        end
        
        % Cleanup after loop stops
        statusText.Text = 'Status: Idle';
        startBtn.Text = 'Start';
        horizon.Pitch = 0;
        horizon.Roll = 0;
    end
end