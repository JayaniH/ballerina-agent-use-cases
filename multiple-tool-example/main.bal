import ballerina/file;
import ballerina/http;
import ballerina/io;
import ballerinax/ai.agent;
import ballerinax/dataflowkit;
import ballerinax/googleapis.gmail;
import ballerinax/googleapis.sheets;
import ballerina/lang.array;
import ballerina/time;

configurable string googleToken = ?;
configurable string openAIToken = ?;
configurable string dataflowkitToken = ?;
configurable string mediumToken = ?;
configurable string googleSearchApiKey = ?;
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

type SendEmailInput record {|
    string recipientEmail;
    string emailSubject;
    string emailBody;
|};

type SearchEmailThreadInput record {|
    string searchQuery;
|};

type ReadEmailThreadInput record {|
    string threadId;
|};

type Base64Input record {|
    string 'string;
|};

type ScrapeWebsiteInput record {|
    string url;
|};

final gmail:Client gmail = check new ({auth: {token: googleToken}});
final sheets:Client gSheets = check new ({auth: {token: googleToken}});

public function main() returns error? {

    string query = "Do I have any email threads about birthdays?";

    // 1) Create the model (brain of the agent)
    agent:ChatGptModel model = check new ({auth: {token: openAIToken}});

    // 2) Define functions as tools 
    agent:Tool readFileTool = {
        name: "Read_File",
        description: "useful to read contents of a file (string or byte array) from a given path",
        inputSchema: {
            'type: agent:OBJECT,
            properties: {
                filepath: {'type: agent:STRING},
                fileType: {'type: agent:STRING, 'enum: ["STRING", "BYTE"]}
            },
            required: ["filepath", "fileType"]
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
                fileType: {'type: agent:STRING, 'enum: ["STRING", "BYTE"]},
                content: {anyOf: [{'type: agent:STRING}, {'type: agent:ARRAY, 'items: {'type: agent:INTEGER}}]}
            },
            required: ["filepath", "fileType", "content"]
        },
        caller: writeFile
    };

    agent:Tool searchFileTool = {
        name: "Search_For_File",
        description: "useful to find whether a particular file exists at a given path",
        inputSchema: {
            'type: agent:OBJECT,
            properties: {
                filepath: {'type: agent:STRING, description: "path to the file to be searched, including the file name"}
            },
            required: ["filepath"]
        },
        caller: searchFile
    };

    agent:Tool calculatorTool = {
        name: "Basic_Calculator",
        description: "useful to do basic arithmetic operations (addition, subtraction, multiplication, division) for two given numbers",
        inputSchema: {
            'type: agent:OBJECT,
            properties: {
                operation: {'type: agent:STRING, 'enum: ["ADDITION", "SUBSTRACTION", "MULTIPLICATION", "DIVISION"]},
                operand1: {'type: agent:FLOAT, description: "first operand/number as a float. if the number is an integer, it should be converted to a float"},
                operand2: {'type: agent:FLOAT, description: "second operand/number as a float. if the number is an integer, it should be converted to a float"}
            },
            required: ["operation", "operand1", "operand2"]
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
                downloadPath: {'type: agent:STRING, description: "path to the downloaded, including the file name"}
            },
            required: ["url", "downloadPath"]
        },
        caller: downloadFile
    };

    agent:Tool readGoogleSheetsTool = {
        name: "Read_Google_Sheets",
        description: "useful to read content from a google sheet",
        inputSchema: {
            'type: agent:OBJECT,
            properties: {
                spreadsheetId: {'type: agent:STRING, description: "id of the google sheet which can be found in the url of the sheet. e.g. 1kklddHCSpU8yBSCIbrE97-Ry9ugaS7xMIIH1cb37VPE"},
                sheetName: {'type: agent:STRING, description: "name of the worksheet to be read"},
                range: {'type: agent:STRING, description: "range of cells to be read. e.g. A1:B2"}
            },
            required: ["spreadsheetId", "sheetName", "range"]
        },
        caller: readGoogleSheets
    };

    agent:Tool sendEmailTool = {
        name: "Send_Email",
        description: "useful to construct an email in HTML format and send it to a given recipient",
        inputSchema: {
            'type: agent:OBJECT,
            properties: {
                recipientEmail: {'type: agent:STRING},
                emailSubject: {'type: agent:STRING},
                emailBody: {'type: agent:STRING, description: "body of the email in HTML format including relevant image links. e.g. <p>[TEXT]</p> <br/> <img src=[imageURL]>"}
            },
            required: ["recipientEmail", "emailSubject", "emailBody"]
        },
        caller: sendEmail
    };

    agent:Tool searchEmailThreadsTool = {
        name: "Search_Email_Threads",
        description: "useful to search for email threads in the inbox based on a given query",
        inputSchema: {
            'type: agent:OBJECT,
            properties: {
                searchQuery: {'type: agent:STRING, description: "query to be searched to find the relevant email threads"}
            },
            required: ["searchQuery"]
        },
        caller: searchEmailThread
    };

    agent:Tool readEmailThreadsTool = {
        name: "Read_Email_Thread",
        description: "useful to read the contents of an email thread",
        inputSchema: {
            'type: agent:OBJECT,
            properties: {
                theadId: {'type: agent:STRING, description: "id of the email thread to be read. this can be found in the email thread search results."}
            },
            required: ["theadId"]
        },
        caller: readEmailThread
    };

    // This is re-implemented as a HTTP tool
    // agent:Tool scrapeWebsiteTool = {
    //     name: "Scrape_Website",
    //     description: "useful to scrape content from a website",
    //     inputSchema: {
    //         'type: agent:OBJECT,
    //         properties: {
    //             url: {'type: agent:STRING, description: "url of the website to be scraped"}
    //         },
    //         required: ["url"]
    //     },
    //     caller: scrapeWebsite
    // };

    agent:Tool encodeBase64Tool = {
        name: "Base64_Encode",
        description: "always use this to encode a given text to base64",
        inputSchema: {
            'type: agent:OBJECT,
            properties: {
                'string: {'type: agent:STRING, description: "plain text to be encoded"}
            },
            required: ["string"]
        },
        caller: encodeBase64
    };

    agent:Tool decodeBase64Tool = {
        name: "Base64_Decode",
        description: "always use this to decode a base64 encoded string to plain text",
        inputSchema: {
            'type: agent:OBJECT,
            properties: {
                'string: {'type: agent:STRING, description: "base64 encoded string to be decoded"}
            },
            required: ["string"]
        },
        caller: decodeBase64
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
            },
            required: ["prompt", "model"]
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
                max_tokens: {'type: agent:INTEGER, default: 1000},
                temperature: {'type: agent:FLOAT, default: 0.7}
            },
            required: ["prompt", "model"]
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
            },
            required: ["prompt"]
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
            },
            required: ["prompt", "model"]
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
            },
            required: ["file", "model"]
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
            },
            required: ["prompt", "model"]
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
                'key: {'type: agent:STRING, default: googleSearchApiKey},
                cx: {'type: agent:STRING, default: searchEngineId},
                q: {'type: agent:STRING, description: "the search query"}
            },
            required: ["key", "cx", "q"]
        }
    };

    agent:HttpServiceToolKit googleSearchToolKit = check new ("https://www.googleapis.com", [googleSearchTool]);

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
            },
            required: ["timeMin", "timeMax"]
        }
    };

    // This is re-implemented as a funtion tool wrapping the connector
    // agent:HttpTool gmailTool = {
    //     name: "Send_Email",
    //     path: "gmail/v1/users/me/messages/send",
    //     method: agent:POST,
    //     description: string `useful to send an email. the email should be base64 encoded.`,
    //     requestBody: {
    //         'type: agent:OBJECT,
    //         properties: {
    //             raw: {
    //                 'type: agent:STRING,
    //                 format: "base64",
    //                 description: string `the base64 encoded raw email message. message format should be as follows prior to encoding:" +
    //                 "To:[RECEIVER_EMAIL_ADDRESS]
    //                 Subject: [SUBJECT]
    //                 Content-Type: text/html; charset=UTF-8

    //                 <p>[MESSAGE_BODY]</p> <br/> <img src="[IMAGE_URL]">`
    //             }
    //         }
    //     }
    // };

    agent:HttpServiceToolKit googleToolKit = check new ("https://www.googleapis.com", [googleCalendarEventsTool], {auth: {token: googleToken}});

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
            },
            required: ["title", "contentFormat", "content"]
        }
    };

    agent:HttpServiceToolKit mediumToolkit = check new ("https://api.medium.com", [mediumUserTool, postMediumArticleTool], {auth: {token: mediumToken}});

    agent:HttpTool scrapeWebsiteTool = {
        name: "Scrape_Website",
        path: "/v1/fetch",
        method: agent:POST,
        description: "useful to scrape the html from a website",
        queryParams: {
            'type: agent:OBJECT,
            properties: {
                api_key: {'type: agent:STRING, default: dataflowkitToken}
            },
            required: ["api_key"]
        },
        requestBody: {
            'type: agent:OBJECT,
            properties: {
                url: {'type: agent:STRING, description: "the url of the website to scrape"},
                'type: {'type: agent:STRING, default: "base"}            },
            required: ["url", "type"]
        }
    };

    agent:HttpServiceToolKit dataflowkitToolKit = check new ("https://api.dataflowkit.com", [scrapeWebsiteTool]);

    // 3) Create the agent 
    agent:Agent agent = check new (model, readFileTool, writeFileTool, searchFileTool, calculatorTool, downloadFileTool, readGoogleSheetsTool, sendEmailTool, searchEmailThreadsTool, readEmailThreadsTool, encodeBase64Tool, decodeBase64Tool, openaiToolKit, googleSearchToolKit, googleToolKit, mediumToolkit, dataflowkitToolKit);

    // 4) Run the agent with user's query
    decimal time_before = time:monotonicNow();
    _ = agent.run(query, maxIter = 10, context = {"jane_email": "janetest152@gmail.com"});
    decimal time_after = time:monotonicNow();

    io:print("Time taken to run the agent: " + (time_after - time_before).toString() + "s");
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
    sheets:Range range = check gSheets->getRange(input.spreadsheetId, input.sheetName, input.range);
    return range.toString();
}

isolated function sendEmail(*SendEmailInput input) returns string|error {
    gmail:MessageRequest messageRequest = {
        recipient: input.recipientEmail,
        subject: input.emailSubject,
        messageBody: input.emailBody,
        contentType: gmail:TEXT_HTML
    };
    gmail:Message sendMessage = check gmail->sendMessage(messageRequest, userId = "me");
    return sendMessage.toString();
}

isolated function searchEmailThread(*SearchEmailThreadInput input) returns string|error {
    gmail:MailThread[] threads = [];

    stream<gmail:MailThread,error?> threadList = check gmail->listThreads(filter = {includeSpamTrash: false, labelIds: ["INBOX"], q: input.searchQuery});
        
    _ = check from gmail:MailThread thread in threadList 
    do {
        threads.push(thread);
    };
    return threads.toString();
}

isolated function readEmailThread(*ReadEmailThreadInput input) returns string|error {
    gmail:MailThread thread = check gmail->readThread(input.threadId, format = gmail:FORMAT_FULL);
    return thread.toString();
}

isolated function scrapeWebsite(*ScrapeWebsiteInput input) returns string|error {
    dataflowkit:Client dataflowkitClient = check new ({apiKey: dataflowkitToken});
    json response = check dataflowkitClient->fetch({url: input.url, 'type: "base"});
    return response.toString();
}

isolated function encodeBase64(*Base64Input input) returns string|error {
    return input.'string.toBytes().toBase64();
}

isolated function decodeBase64(*Base64Input input) returns string|error {
    byte[] decoded = check array:fromBase64(input.'string);
    return check string:fromBytes(decoded);
}
