using System;
using System.Collections.Generic;
using System.Configuration;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace VHDL_FSM_Visualizer
{
    class Utils
    {

        public static Form1 form { get; set; }

        public enum logType { Info, Error, Warning, Debug };
        static int fsmDeclarationLine = -1;
        static int lineOfOpenEnum = -1, indexOfOpenEnum = -1, lineOfCloseEnum = -1, indexOfCloseEnum = -1;
        static string fsmDeclerationText = "";

        static int fsmCaseStartLine = -1, fsmCaseEndLine = -1;
        static string caseStatementStr = "";

        public static List<FSM_State> vhdlParseStatesDecleration(string[] linesOfCode, string fsmTypeVariable)
        {
            List<FSM_State> fsmStates = new List<FSM_State>();
            lineOfOpenEnum = -1;
            indexOfOpenEnum = -1;
            lineOfCloseEnum = -1;
            indexOfCloseEnum = -1;
            fsmDeclerationText = "";
            fsmDeclarationLine = -1;
            fsmCaseStartLine = -1;
            fsmCaseEndLine = -1;
            caseStatementStr = "";
            try
            {
                bool fsmTypeFound = false;
                //Find the code line declaring the specified FSM enum for fsmTypeVariable
                for (int i = 0; i < linesOfCode.Length; i++)
                {
                    if (linesOfCode[i].Contains(fsmTypeVariable))
                    {
                        fsmTypeFound = true;
                        fsmDeclarationLine = i;
                        break;
                    }
                }
                for (int i = fsmDeclarationLine; i < linesOfCode.Length; i++)
                {
                    string locTemp = linesOfCode[i];
                    if ((indexOfOpenEnum = locTemp.IndexOf("(")) != -1)
                    {
                        lineOfOpenEnum = i;
                        for (int j = i; j < linesOfCode.Length; j++)
                        {
                            fsmDeclerationText += linesOfCode[j];
                            if ((indexOfCloseEnum = linesOfCode[j].IndexOf(");")) != -1)
                            {
                                lineOfCloseEnum = j;
                                break;
                            }
                        }
                        if (lineOfCloseEnum != -1)
                        {
                            break;
                        }
                    }
                }
                //Clear the string
                if (fsmDeclerationText.IndexOf("type", StringComparison.CurrentCultureIgnoreCase) != -1)
                {
                    fsmDeclerationText = fsmDeclerationText.Remove(fsmDeclerationText.IndexOf("type", StringComparison.CurrentCultureIgnoreCase), indexOfOpenEnum - fsmDeclerationText.IndexOf("type", StringComparison.CurrentCultureIgnoreCase));
                }
                else if (fsmDeclerationText.IndexOf("(") != -1)
                {
                    fsmDeclerationText = fsmDeclerationText.Remove(fsmDeclerationText.IndexOf("("), indexOfOpenEnum - fsmDeclerationText.IndexOf("("));
                }
                fsmDeclerationText = RemoveSpecialCharacters(fsmDeclerationText);
                //Split just the state names
                string[] statesText = fsmDeclerationText.Split(new string[] { "," }, StringSplitOptions.RemoveEmptyEntries);
                fsmStates = new List<FSM_State>(statesText.Length);
                //Create the states
                for (int i = 0; i < statesText.Length; i++)
                {
                    fsmStates.Add(new FSM_State(i, statesText[i]));
                }
            }
            catch (Exception ex)
            {
                Utils.WriteLogFile(Utils.logType.Error, "Exception occured with message: " + ex.Message, "Data: \n" + ex.Data);
            }

            return fsmStates;
        }

        public static string[] vhdlRemoveComments(string[] linesOfCode)
        {
            List<string> linesWithoutComents = new List<string>(linesOfCode.Length);
            for (int i = 0; i < linesOfCode.Length; i++)
            {
                linesWithoutComents.Add(RemoveComments(linesOfCode[i]));
            }
            return linesWithoutComents.ToArray();
        }

        public static List<FSM_State> vhdlParseStatesTransitions(List<FSM_State> fsmStates, string[] linesOfCode, string fsmCurrStateVar, string fsmNextStateVar)
        {
            //Find the case statement corresponding to the FSM defined by fsmCurrStateVar
            for (int i = lineOfCloseEnum; i < linesOfCode.Length; i++)
            {
                string line = linesOfCode[i];
                if (CaseForFSMExists(line, fsmCurrStateVar))
                {
                    fsmCaseStartLine = i;
                }
                else if (EndCaseForFSMExists(line) && fsmCaseStartLine != -1)
                {
                    fsmCaseEndLine = i;
                    break;
                }
            }
            //Concate the text corresponding to the FSM defined by fsmCurrStateVar
            if (fsmCaseStartLine != -1 && fsmCaseEndLine != -1)
            {
                for (int i = fsmCaseStartLine; i <= fsmCaseEndLine; i++)
                {
                    caseStatementStr += linesOfCode[i];
                }
                //Find the starting & ending lines numbers of each WHEN text foreach STATE in fsmStates
                FSM_State tempState = null, prevState = null;
                for (int i = fsmCaseStartLine; i <= fsmCaseEndLine; i++)
                {
                    string line = linesOfCode[i].Replace("\t", String.Empty).Replace("\n", String.Empty);

                    if ((tempState = GetStateBelongsToWhen(line, fsmStates)) != null)
                    {
                        tempState.whenStmentStartLine = i;
                        if (prevState != null)
                        {
                            prevState.whenStmentEndLine = i;
                        }
                        prevState = tempState;
                    }
                    else if (EndCaseForFSMExists(line) && prevState != null)
                    {
                        prevState.whenStmentEndLine = i;
                    }
                }
                //Concate the WHEN text foreach STATE foreach state in fsmStates
                for (int ii = 0; ii < fsmStates.Count; ii++)
                {
                    FSM_State state = fsmStates[ii];
                    StringBuilder sb = new StringBuilder();
                    if (state.whenStmentStartLine != -1 && state.whenStmentEndLine != -1)
                    {
                        for (int i = state.whenStmentStartLine; i < state.whenStmentEndLine; i++)
                        {
                            string line = RemoveLeadingMultiTabs(linesOfCode[i]);
                            sb.AppendLine(line);
                        }
                        state.whenStmentTxt = sb.ToString().Replace("\t", "  ");
                        Utils.WriteLogFile(Utils.logType.Debug, "State: " + state.name + " ", state.whenStmentTxt.Replace("\t", " "));
                    }
                    else
                    {
                        Utils.WriteLogFile(Utils.logType.Debug, "State: " + state.name + " doesn't have a WHEN statement");
                    }
                }
                //TODO: Find transitions to next states foreach state in fsmStates
                foreach (FSM_State state in fsmStates)
                {
                    int startIfLine = -1, endIfLine = -1, startElseLine = -1;
                    int ifsCount = 0;
                    for (int i = state.whenStmentStartLine; i < state.whenStmentEndLine; i++)
                    {
                        string line = linesOfCode[i].Replace("\t", String.Empty).Replace("\n", String.Empty);
                        if (ifsCount == 0 && line.IndexOf(fsmNextStateVar) != -1) //transition found outside of Condition
                        {
                            FSM_State next_state = GetStateForTransition(line, fsmStates, fsmNextStateVar);
                            if (next_state != null)
                            {
                                state.next_states.Add(next_state, "always");
                            }
                            else
                            {
                                Utils.WriteLogFile(logType.Error, "line #" + (i + 1) + ": " + line + " has an unknown next state");
                            }
                        }
                        else if (i > startIfLine && (i<startElseLine || startElseLine==-1) && line.IndexOf(fsmNextStateVar) != -1)
                        {
                            FSM_State next_state = GetStateForTransition(line, fsmStates, fsmNextStateVar);
                            if (next_state != null)
                            {
                                try
                                {
                                    state.next_states.Add(next_state, KeepOnlyConditionText(linesOfCode[startIfLine]));
                                }
                                catch (Exception ex)
                                {
                                    Utils.WriteLogFile(logType.Error, "line #" + (i + 1) + ": " + line + " could not add state transition" + state.name +"->"+next_state.name);
                                }
                            }
                            else
                            {
                                Utils.WriteLogFile(Utils.logType.Error, "line #" + (i + 1) + ": " + line + " has an unknown next state");
                            }
                        }
                        else if (i > startElseLine && line.IndexOf(fsmNextStateVar) != -1)
                        {
                            FSM_State next_state = GetStateForTransition(line, fsmStates, fsmNextStateVar);
                            if (next_state != null)
                            {
                                try
                                {
                                    state.next_states.Add(next_state, "not(" + KeepOnlyConditionText(linesOfCode[startIfLine]) + ")");
                                }
                                catch (Exception ex)
                                {
                                    Utils.WriteLogFile(logType.Error, "line #" + (i + 1) + ": " + line + " could not add state transition" + state.name + "->" + next_state.name);
                                }
                            }
                            else
                            {
                                Utils.WriteLogFile(logType.Error, "line #" + (i + 1) + ": " + line + " has an unknown next state");
                            }
                        }
                        if (IsIfStatement(line))
                        {
                            startIfLine = i;
                            ifsCount++;
                        }
                        else if (IsElseIfStatement(line))
                        {
                            startIfLine = i;
                        }
                        else if (IsElseStatement(line))
                        {
                            startElseLine = i;
                        }
                        else if (IsEndIfStatement(line))
                        {
                            ifsCount--;
                        }
                    }
                }
            }
            else
            {
                WriteLogFile(logType.Debug, "Case statement could not be found for variable", fsmCurrStateVar);
            }

            return fsmStates;
        }

        public static FSM_State GetStateForTransition(string line, List<FSM_State> states, string fsmNextStateVar)
        {
            foreach (FSM_State state in states)
            {
                if (Regex.IsMatch(line, fsmNextStateVar + @"(\s+|\t+)?<=(\s+|\t+)?(?:^|)" + state.name + @"(?:$|\W)", RegexOptions.IgnoreCase))
                {
                    return state;
                }
            }
            return null;
        }

        public static FSM_State GetStateBelongsToWhen(string line, List<FSM_State> states)
        {
            foreach (FSM_State state in states)
            {
                if (Regex.IsMatch(line, @"when(\s+|\t+)" + state.name + @"(\s+|\t+)?=>", RegexOptions.IgnoreCase))
                {
                    return state;
                }
            }
            if (Regex.IsMatch(line, @"when(\s+|\t+)(.+?)=>", RegexOptions.IgnoreCase)) //capture an unknown state i.e.: WHEN others =>
            {
                return new FSM_State(-1, "");
            }
            else //nothing found
            {
                return null;
            }
        }

        public static bool IsNextStateAssign(string line, string fsmNextStateVar)
        {
            return Regex.IsMatch(line, fsmNextStateVar + @"(\s+|\t+)<=(.*?);", RegexOptions.Compiled);
        }

        public static bool IsIfStatement(string line)
        {
            return Regex.IsMatch(line, @"if(\s+|\t+)(.*?)then", RegexOptions.IgnoreCase);
        }

        public static bool IsElseIfStatement(string line)
        {
            return Regex.IsMatch(line, @"elsif(\s+|\t+)(.*?)then", RegexOptions.IgnoreCase);
        }

        public static bool IsElseStatement(string line)
        {
            return Regex.IsMatch(line, @"else", RegexOptions.IgnoreCase);
        }

        public static bool IsEndIfStatement(string line)
        {
            return Regex.IsMatch(line, @"end(\s+|\t+)if;", RegexOptions.IgnoreCase);
        }

        public static bool CaseForFSMExists(string line, string fsmCurrStateVar)
        {
            return Regex.IsMatch(line, @"case(\s+|\t+)" + fsmCurrStateVar + @"(\s+|\t+)is", RegexOptions.IgnoreCase);
        }

        public static bool EndCaseForFSMExists(string line)
        {
            return Regex.IsMatch(line, @"end(\s+|\t+)case;", RegexOptions.IgnoreCase);
        }

        public static string RemoveNonCodeCharacters(string str)
        {
            return Regex.Replace(str, @"[^a-zA-Z0-9_.,;\(\)\{\}]+", String.Empty, RegexOptions.Compiled);
        }

        public static string RemoveComments(string str)
        {
            return Regex.Replace(str, @"\-\-.*", String.Empty, RegexOptions.Compiled);
        }

        public static string RemoveSpecialCharacters(string str)
        {
            return Regex.Replace(str, "[^a-zA-Z0-9_.,]+", String.Empty, RegexOptions.Compiled);
        }

        public static string KeepOnlyConditionText(string str)
        {
            return Regex.Replace(str, @"(if|then|elsif|\t+)", String.Empty, RegexOptions.IgnoreCase);
        }

        public static string RemoveLeadingMultiTabs(string str)
        {
            return Regex.Replace(str, @"^([\t]\t)", String.Empty, RegexOptions.Compiled);
        }

        public static void WriteLogFile(logType type, string message, string extras = "")
        {
            System.Configuration.Configuration config = ConfigurationManager.OpenExeConfiguration(ConfigurationUserLevel.None);
            if (form != null)
            {
                if (type == logType.Debug)
                {
                    if (bool.Parse(config.AppSettings.Settings["DebugMode"].Value.ToString()))
                    {
                        form.LogOutput.Items.Add(DateTime.Now.ToString("HH:mm:ss") + ": ----" + type.ToString() + ":  " + message + "  " + extras);
                    }
                }
                else
                {
                    form.LogOutput.Items.Add(DateTime.Now.ToString("HH:mm:ss") + ": ----" + type.ToString() + ":  " + message + "  " + extras);
                }

                form.LogOutput.SelectedIndex = form.LogOutput.Items.Count - 1;
                form.LogOutput.SelectedIndex = -1;
            }
            else
            {
                return;
            }
        }
    }
}
