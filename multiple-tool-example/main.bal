import ballerina/file;
import ballerina/http;
import ballerina/io;
import ballerinax/ai.agent;
import ballerinax/dataflowkit;
import ballerinax/googleapis.sheets;

configurable string googleToken = ?;
configurable string openAIToken = ?;
configurable string dataflowkitToken = ?;
configurable string mediumToken = ?;
configurable string googleApiKey = ?;
configurable string searchEngineId = ?;

enum FileType {
    STRING,
    BYTE
};

enum CalculateOpTypes {
    ADDITION,
    SUBSTRACTION,
    MULTIPLICATION,
    DIVISION
};

type ReadFileInput record {|
    string filepath;
    FileType fileType;
|};

type WriteFileInput record {|
    string filepath;
    string|byte[] content;
    FileType fileType;
|};

type SearchFileInput record {|
    string filepath;
|};

type CalculatorInput record {|
    CalculateOpTypes operation;
    float operand1;
    float operand2;
|};

type DownloadFileInput record {|
    string url;
    string downloadPath;
|};

type GoogleSheetsInput record {|
    string spreadsheetId;
    string sheetName;
    string range;
|};

type EncodeBase64Input record {|
    string text;
|};

type ScrapeWebsiteInput record {|
    string url;
|};

public function main() returns error? {

    string query = "It's Jane's birthday. Send her my wishes.";

    // 1) Create the model (brain of the agent)
    agent:Gpt3Model model = check new ({auth: {token: openAIToken}});

    // 2) Define functions as tools 
    agent:Tool readFileTool = {
        name: "Read_File",
        description: "useful to read contents of a file (string or byte array) from a given path",
        inputSchema: {
            'type: agent:OBJECT,
            properties: {
                filepath: {'type: agent:STRING},
                fileType: {'type: agent:STRING, 'enum: ["STRING", "BYTE"]}
            }
        },
        caller: readFile
    };

    agent:Tool writeFileTool = {
        name: "Write_File",
        description: "useful to write contents (string or byte array) to a file at a given path",
        inputSchema: {
            'type: agent:OBJECT,
            properties: {
                filepath: {'type: agent:STRING},
                fileType: {'type: agent:STRING},
                content: {anyOf: [{'type: agent:STRING}, {'type: agent:ARRAY, 'items: {'type: agent:INTEGER}}]}
            }
        },
        caller: writeFile
    };

    agent:Tool searchFileTool = {
        name: "Search_File",
        description: "useful to find whether a particular file exists at a given path",
        inputSchema: {
            'type: agent:OBJECT,
            properties: {
                filepath: {'type: agent:STRING}
            }
        },
        caller: searchFile
    };

    agent:Tool calculatorTool = {
        name: "Basic_Calculator",
        description: "useful to do basic arithmetic operations (addition, subtraction, multiplication, division)",
        inputSchema: {
            'type: agent:OBJECT,
            properties: {
                operation: {'type: agent:STRING},
                operand1: {'type: agent:FLOAT},
                operand2: {'type: agent:FLOAT}
            }
        },
        caller: basicCalculator
    };

    agent:Tool downloadFileTool = {
        name: "Download_File",
        description: "useful to download content from a url to a given path",
        inputSchema: {
            'type: agent:OBJECT,
            properties: {
                url: {'type: agent:STRING},
                downloadPath: {'type: agent:STRING}
            }
        },
        caller: downloadFile
    };

    agent:Tool readGoogleSheetsTool = {
        name: "Read_Google_Sheets",
        description: "useful to read content from a google sheet",
        inputSchema: {
            'type: agent:OBJECT,
            properties: {
                spreadsheetId: {'type: agent:STRING},
                sheetName: {'type: agent:STRING},
                range: {'type: agent:STRING}
            }
        },
        caller: readGoogleSheets
    };

    agent:Tool scrapeWebsiteTool = {
        name: "Scrape_Website",
        description: "useful to scrape content from a website",
        inputSchema: {
            'type: agent:OBJECT,
            properties: {
                url: {'type: agent:STRING}
            }
        },
        caller: scrapeWebsite
    };

    agent:Tool encodeBase64Tool = {
        name: "Base64_Encode",
        description: "always use this to encode a given text to base64",
        inputSchema: {
            'type: agent:OBJECT,
            properties: {
                text: {'type: agent:STRING}
            }
        },
        caller: encodeBase64
    };

    agent:HttpTool generateContentTool = {
        name: "Generate_Content",
        path: "/v1/completions",
        method: agent:POST,
        description: "useful to generate text content using a given instruction and description",
        requestBody: {
            'type: agent:OBJECT,
            properties: {
                prompt: {'type: agent:STRING, description: "the instruction which states information about the text to be generated"},
                model: {'type: agent:STRING, default: "text-davinci-003"},
                max_tokens: {'type: agent:INTEGER, default: 200},
                temperature: {'type: agent:FLOAT, default: 0.7}
            }
        }
    };

    agent:HttpTool generateCodeTool = {
        name: "Generate_Python_Code",
        path: "/v1/completions",
        method: agent:POST,
        description: "useful to generate python code using a given instruction and description",
        requestBody: {
            'type: agent:OBJECT,
            properties: {
                prompt: {'type: agent:STRING, description: "the instruction which states information about the code to be generated"},
                model: {'type: agent:STRING, default: "text-davinci-003"},
                max_tokens: {'type: agent:INTEGER, default: 200},
                temperature: {'type: agent:FLOAT, default: 0.7}
            }
        }
    };

    agent:HttpTool generateImageTool = {
        name: "Generate_Image",
        path: "/v1/images/generations",
        method: agent:POST,
        description: "always use this to generate an image from a given instruction",
        requestBody: {
            'type: agent:OBJECT,
            properties: {
                prompt: {'type: agent:STRING, description: "the instruction which states information about the content to be generated"},
                response_format: {'type: agent:STRING, 'enum: ["url", "b64_json"], default: "url"}
            }
        }
    };

    agent:HttpTool summarizationTool = {
        name: "Summarize_Text",
        path: "/v1/completions",
        method: agent:POST,
        description: "useful to summarize a given text",
        requestBody: {
            'type: agent:OBJECT,
            properties: {
                prompt: {'type: agent:STRING, pattern: "Summarize the following text: \n <TEXT_CONTENT>"},
                model: {'type: agent:STRING, default: "text-davinci-003"},
                max_tokens: {'type: agent:INTEGER, default: 1000},
                temperature: {'type: agent:FLOAT, default: 0.7}
            }
        }
    };

    agent:HttpTool transcriptionTool = {
        name: "Transcribe_Audio",
        path: "/v1/audio/transcriptions",
        method: agent:POST,
        description: "useful to transcribe a given audio file",
        requestBody: {
            'type: agent:OBJECT,
            properties: {
                file: {'type: agent:STRING, pattern: "@<{AUDIO_FILE_PATH>"},
                model: {'type: agent:STRING, default: "whisper-1"}
            }
        }
    };

    agent:HttpTool translationTool = {
        name: "Translate_Text",
        path: "/v1/completions",
        method: agent:POST,
        description: "useful to translate a given text to a given language",
        requestBody: {
            'type: agent:OBJECT,
            properties: {
                prompt: {'type: agent:STRING, pattern: "Translate the following text to <TARGET_LANGUAGE>: \n <TEXT_CONTENT>"},
                model: {'type: agent:STRING, default: "text-davinci-003"},
                max_tokens: {'type: agent:INTEGER, default: 1000},
                temperature: {'type: agent:FLOAT, default: 0.7}
            }
        }
    };

    agent:HttpServiceToolKit openaiToolKit = check new ("https://api.openai.com", [generateContentTool, generateCodeTool, summarizationTool, generateImageTool, translationTool, transcriptionTool], {
        auth: {
            token: openAIToken
        }
    });

    agent:HttpTool googleSearchTool = {
        name: "Google_Search",
        path: "/customsearch/v1",
        method: agent:GET,
        description: "useful to summarize a given text",
        queryParams: {
            'type: agent:OBJECT,
            properties: {
                'key: {'type: agent:STRING, default: googleApiKey},
                cx: {'type: agent:STRING, default: searchEngineId},
                q: {'type: agent:STRING, description: "the search query"}
            }
        }
    };

    agent:HttpTool googleCalendarEventsTool = {
        name: "Get_Calendar_Events",
        path: "/calendar/v3/calendars/{calendarId}/events",
        method: agent:GET,
        description: "useful to summarize a given text. the calendarId is the email address of the calendar user",
        queryParams: {
            'type: agent:OBJECT,
            properties: {
                timeMin: {'type: agent:STRING, description: "lower bound (inclusive) for an event's end time to filter by", pattern: "2011-06-03T10:00:00Z"},
                timeMax: {'type: agent:STRING, description: "upper bound (exclusive) for an event's start time to filter by", pattern: "2011-06-03T10:00:00Z"}
            }
        }
    };

    agent:HttpTool gmailTool = {
        name: "Send_Email",
        path: "gmail/v1/users/me/messages/send",
        method: agent:POST,
        description: string `useful to send an email. the email should be base64 encoded.`,
        requestBody: {
            'type: agent:OBJECT,
            properties: {
                raw: {
                    'type: agent:STRING,
                    format: "base64",
                    description: string `the base64 encoded raw email message. message format should be as follows prior to encoding:" +
                    "To:[RECEIVER_EMAIL_ADDRESS]
                    Subject: [SUBJECT]
                    Content-Type: text/html; charset=UTF-8

                    <p>[MESSAGE_BODY]</p> <br/> <img src="[IMAGE_URL]">`
                }
            }
        }
    };

    agent:HttpServiceToolKit googleToolKit = check new ("https://www.googleapis.com", [googleSearchTool, googleCalendarEventsTool, gmailTool], {auth: {token: googleToken}});

    agent:HttpTool mediumUserTool = {
        name: "Get_Medium_User_Details",
        path: "/v1/me",
        method: agent:GET,
        description: "useful to fetch the user data of the medium user"
    };

    agent:HttpTool postMediumArticleTool = {
        name: "Post_Medium_Article",
        path: "/v1/users/{authorId}/posts",
        method: agent:POST,
        description: "useful to post an article on medium",
        requestBody: {
            'type: agent:OBJECT,
            properties: {
                title: {'type: agent:STRING},
                contentFormat: {'type: agent:STRING, 'enum: ["html", "markdown"], default: "markdown"},
                content: {'type: agent:STRING}
            }
        }
    };

    agent:HttpServiceToolKit mediumToolkit = check new ("https://api.medium.com", [mediumUserTool, postMediumArticleTool], {auth: {token: mediumToken}});

    // 3) Create the agent 
    agent:Agent agent = check new (model, readFileTool, writeFileTool, searchFileTool, calculatorTool, downloadFileTool, readGoogleSheetsTool, scrapeWebsiteTool, encodeBase64Tool, openaiToolKit, googleToolKit, mediumToolkit);

    // 4) Run the agent with user's query
    _ = agent.run(query, maxIter = 10, context = {"jane_email": "janetest152@gmail.com"});
}

isolated function writeFile(*WriteFileInput input) returns string|error? {
    string|byte[] content = input.content;
    if input.fileType == STRING && content is string {
        check io:fileWriteString(input.filepath, content);
        return "Successfully written to file";
    }
    else if input.fileType == BYTE && content is byte[] {
        check io:fileWriteBytes(input.filepath, content);
        return "Successfully written to file";
    }
    else {
        return error("Invalid file type");
    }
}

isolated function readFile(*ReadFileInput input) returns string|byte[]|error? {
    if input.fileType == STRING {
        return check io:fileReadString(input.filepath);
    }
    else if input.fileType == BYTE {
        return check io:fileReadBytes(input.filepath);
    }
    else {
        return error("Invalid file type");
    }
}

isolated function searchFile(*SearchFileInput input) returns string|error {
    boolean fileExists = check file:test(input.filepath, file:EXISTS);
    if fileExists {
        return "File exists";
    }
    else {
        return "File does not exist";
    }
}

isolated function basicCalculator(*CalculatorInput input) returns float|error {
    if input.operation == ADDITION {
        return input.operand1 + input.operand2;
    }
    else if input.operation == SUBSTRACTION {
        return input.operand1 - input.operand2;
    }
    else if input.operation == MULTIPLICATION {
        return input.operand1 * input.operand2;
    }
    else if input.operation == DIVISION {
        return input.operand1 / input.operand2;
    }
    else {
        return error("Invalid operation");
    }
}

isolated function downloadFile(*DownloadFileInput input) returns string|error {
    http:Client httpClient = check new (input.url);
    http:Response httpResp = check httpClient->/get();
    byte[] audioBytes = check httpResp.getBinaryPayload();
    check io:fileWriteBytes(input.downloadPath, audioBytes);
    return string `Successfully downloaded audio to file ${input.downloadPath}`;
}

isolated function readGoogleSheets(*GoogleSheetsInput input) returns string|error {
    final sheets:Client gSheets = check new ({auth: {token: googleToken}});
    sheets:Range range = check gSheets->getRange(input.spreadsheetId, input.sheetName, input.range);
    return range.toString();
}

isolated function scrapeWebsite(*ScrapeWebsiteInput input) returns string|error {
    dataflowkit:Client dataflowkitClient = check new ({apiKey: dataflowkitToken});
    json response = check dataflowkitClient->fetch({url: input.url, 'type: "base"});
    return response.toString();
}

isolated function encodeBase64(*EncodeBase64Input input) returns string|error {
    return input.text.toBytes().toBase64();
}
