function chosen = chooseReceiverProjectPopup(projects, tbl)
                % Modal dialog that blocks until OK/Cancel
                % Returns chosen project (string) or "" if cancelled
        

                % projects: string or cellstr or char? Normalize to string.
                projects = string(projects);

                % Optional: show counts per project (nice UX)
                proj = strtrim(string(tbl.RCV_PROJECT));
                proj(strlength(proj)==0 | ismissing(proj) | strcmpi(proj,"nan")) = missing;
        
                counts = arrayfun(@(p) sum(proj == p), projects);
                
                % Build display labels as a string array
                labels = compose("%s  (n=%d)", projects, counts);
                
                % Ensure 1xN row vector
                labels = labels(:)';          % row string array
                projects = projects(:)';      % row string array
                
                % Convert to cell array of char vectors (always accepted)
                itemsCell = cellstr(labels);  % 1xN cell of char vectors

                chosen = "";
        
                d = uifigure( ...
                    'Name', 'Select Receiver Project', ...
                    'WindowStyle', 'modal', ...
                    'Position', [300 300 520 210]);
        
                msg = sprintf("Metadata contains %d Receiver Projects.\nSelect ONE to keep. All other rows will be removed.", numel(projects));
                uilabel(d, ...
                    'Position', [20 145 480 50], ...
                    'Text', msg, ...
                    'WordWrap', 'on');
        
                dd = uidropdown(d, ...
                    'Position', [20 115 480 28], ...
                    'Items', itemsCell, ...
                    'Value', itemsCell{1});
        
                % OK / Cancel buttons
                uibutton(d, 'Text', 'OK', ...
                    'Position', [320 20 180 40], ...
                    'ButtonPushedFcn', @(~,~) onOK());
        
                uibutton(d, 'Text', 'Cancel', ...
                    'Position', [20 20 180 40], ...
                    'ButtonPushedFcn', @(~,~) onCancel());
        
                % Wait for user action
                uiwait(d);
        
                % --- nested callbacks ---
                function onOK()

                    idx = dd.ValueIndex;        % index of selected item
                    chosen = projects(idx);     % projects is a string array
                    uiresume(d);
                    delete(d);

                end
        
                function onCancel()
                    chosen = "";
                    uiresume(d);
                    delete(d);
                end
        end