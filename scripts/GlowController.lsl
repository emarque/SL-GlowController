// GlowController.lsl - Version 2.0
// Saves and restores glow values across all linked prims
// Integrates with ScheduledVisibility script
// Persists data to cloud API by object UUID

// =====================================================================
// CONFIGURATION
// =====================================================================
string API_BASE_URL = "https://psl.pantherplays.com/api/glow";

// =====================================================================
// GLOBAL VARIABLES
// =====================================================================
key gHttpRequestId;
string gObjectId;

// =====================================================================
// HELPER FUNCTIONS
// =====================================================================

// Convert a list to a pipe-delimited string
string listToPipeString(list lst)
{
    string result = "";
    integer count = llGetListLength(lst);
    integer i = 0;
    while (i < count)
    {
        if (i > 0)
        {
            result += "|";
        }
        result += llList2String(lst, i);
        i++;
    }
    return result;
}

// Parse a pipe-delimited string back to a list of floats
list pipeStringToFloatList(string s)
{
    list parts = llParseString2List(s, ["|"], []);
    list result = [];
    integer count = llGetListLength(parts);
    integer i = 0;
    while (i < count)
    {
        result += [(float)llList2String(parts, i)];
        i++;
    }
    return result;
}

// Parse a pipe-delimited string back to a list of integers
list pipeStringToIntList(string s)
{
    list parts = llParseString2List(s, ["|"], []);
    list result = [];
    integer count = llGetListLength(parts);
    integer i = 0;
    while (i < count)
    {
        result += [(integer)llList2String(parts, i)];
        i++;
    }
    return result;
}

// Build the combined data string: "faceCounts;glowValues"
string buildDataString(list faceCounts, list glowValues)
{
    return listToPipeString(faceCounts) + ";" + listToPipeString(glowValues);
}

// =====================================================================
// GLOW SAVE/RESTORE
// =====================================================================

// Save glow from all linked prims (except root) and send to API
saveAndDisableGlow()
{
    list faceCounts = [];
    list glowValues = [];

    integer linkCount = llGetNumberOfPrims();
    // Start at link 2 to skip root prim (link 1)
    integer link = 2;
    while (link <= linkCount)
    {
        list primParams = llGetLinkPrimitiveParams(link, [PRIM_TYPE]);
        integer faceCount = llGetLinkNumberOfSides(link);
        faceCounts += [faceCount];

        integer face = 0;
        while (face < faceCount)
        {
            list glowParams = llGetLinkPrimitiveParams(link, [PRIM_GLOW, face]);
            float glowValue = llList2Float(glowParams, 0);
            glowValues += [glowValue];
            face++;
        }

        // Disable glow on all faces
        face = 0;
        while (face < faceCount)
        {
            llSetLinkPrimitiveParamsFast(link, [PRIM_GLOW, face, 0.0]);
            face++;
        }

        link++;
    }

    // Send data to API
    string dataStr = buildDataString(faceCounts, glowValues);
    string url = API_BASE_URL + "/" + gObjectId;
    string body = "{\"data\":\"" + dataStr + "\"}";

    gHttpRequestId = llHTTPRequest(url,
        [HTTP_METHOD, "POST",
         HTTP_MIMETYPE, "application/json",
         HTTP_VERIFY_CERT, TRUE],
        body);

    llOwnerSay("GlowController: Saving glow data for " + (string)llGetNumberOfPrims() + " prims.");
}

// Restore glow on all linked prims (except root) from stored data
restoreGlowFromData(string dataStr)
{
    // Split into metadata and values
    list parts = llParseString2List(dataStr, [";"], []);
    if (llGetListLength(parts) < 2)
    {
        llOwnerSay("GlowController: Invalid data format received.");
        return;
    }

    string metaPart = llList2String(parts, 0);
    string valuePart = llList2String(parts, 1);

    list faceCounts = pipeStringToIntList(metaPart);
    list glowValues = pipeStringToFloatList(valuePart);

    integer linkCount = llGetNumberOfPrims();
    integer glowIndex = 0;
    integer linkIndex = 0;

    // Start at link 2 to skip root prim (link 1)
    integer link = 2;
    while (link <= linkCount && linkIndex < llGetListLength(faceCounts))
    {
        integer faceCount = llList2Integer(faceCounts, linkIndex);

        integer face = 0;
        while (face < faceCount && glowIndex < llGetListLength(glowValues))
        {
            float glowValue = llList2Float(glowValues, glowIndex);
            llSetLinkPrimitiveParamsFast(link, [PRIM_GLOW, face, glowValue]);
            face++;
            glowIndex++;
        }

        link++;
        linkIndex++;
    }

    llOwnerSay("GlowController: Glow restored on all linked prims.");
}

// Request glow data from API
restoreGlow()
{
    string url = API_BASE_URL + "/" + gObjectId;
    gHttpRequestId = llHTTPRequest(url,
        [HTTP_METHOD, "GET",
         HTTP_VERIFY_CERT, TRUE],
        "");

    llOwnerSay("GlowController: Requesting glow data from API...");
}

// =====================================================================
// JSON PARSING HELPERS
// =====================================================================

// Extract a string value from a simple JSON object by key
string extractJsonString(string json, string jkey)
{
    string search = "\"" + jkey + "\":\"";
    integer start = llSubStringIndex(json, search);
    if (start == -1)
    {
        return "";
    }
    start += llStringLength(search);
    integer end = llSubStringIndex(llGetSubString(json, start, -1), "\"");
    if (end == -1)
    {
        return "";
    }
    return llGetSubString(json, start, start + end - 1);
}

// =====================================================================
// DEFAULT STATE
// =====================================================================

default
{
    state_entry()
    {
        gObjectId = (string)llGetKey();
        llOwnerSay("GlowController v2.0 ready. Object ID: " + gObjectId);
        llListen(0, "", llGetOwner(), "");
    }

    on_rez(integer startParam)
    {
        gObjectId = (string)llGetKey();
        llOwnerSay("GlowController: Rezzed. Object ID: " + gObjectId);
    }

    touch_start(integer totalNumber)
    {
        if (llDetectedKey(0) == llGetOwner())
        {
            llOwnerSay("GlowController v2.0 Status Check");
            llOwnerSay("  Object UUID: " + gObjectId);
            llOwnerSay("  API URL: " + API_BASE_URL);
            llOwnerSay("  Linked prims: " + (string)(llGetNumberOfPrims() - 1) + " (excluding root)");
        }
    }

    link_message(integer sendingLink, integer num, string str, key id)
    {
        // Integration with ScheduledVisibility script
        // actionMode=1 settings use actionScript=GlowController
        // showFunction triggers restore, hideFunction triggers save
        if (str == "saveGlow" || str == "hide")
        {
            saveAndDisableGlow();
        }
        else if (str == "restoreGlow" || str == "show")
        {
            restoreGlow();
        }
    }

    http_response(key requestId, integer status, list metadata, string body)
    {
        if (requestId != gHttpRequestId)
        {
            return;
        }

        if (status == 200)
        {
            // Check if this is a GET response (contains glow data)
            string dataValue = extractJsonString(body, "data");
            if (dataValue != "")
            {
                restoreGlowFromData(dataValue);
            }
            else
            {
                // POST response - just confirm save
                llOwnerSay("GlowController: Glow data saved successfully.");
            }
        }
        else if (status == 404)
        {
            llOwnerSay("GlowController: No saved glow data found for this object.");
        }
        else
        {
            llOwnerSay("GlowController: API error " + (string)status + ". Body: " + llGetSubString(body, 0, 100));
        }
    }

    listen(integer channel, string name, key id, string message)
    {
        if (id != llGetOwner())
        {
            return;
        }

        string msg = llToLower(message);
        if (msg == "save glow" || msg == "saveglow")
        {
            saveAndDisableGlow();
        }
        else if (msg == "restore glow" || msg == "restoreglow")
        {
            restoreGlow();
        }
        else if (msg == "glow status" || msg == "glowstatus")
        {
            llOwnerSay("GlowController v2.0");
            llOwnerSay("  Object UUID: " + gObjectId);
            llOwnerSay("  API URL: " + API_BASE_URL);
        }
    }
}
