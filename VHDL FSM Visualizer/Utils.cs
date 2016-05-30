using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace VHDL_FSM_Visualizer
{
    class Utils
    {
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
                    fsmStates.Add(new FSM_State (i, statesText[i]));
                }
                //If no states are found
                if (!fsmTypeFound || lineOfOpenEnum == -1 || lineOfCloseEnum == -1 || indexOfOpenEnum == -1 || indexOfCloseEnum == -1)
                {
                    MessageBox.Show("No FSM type enum found in the file selected.", "VHDL FSM Decleration Not Found", MessageBoxButtons.OK, MessageBoxIcon.Exclamation);
                }
            }
            catch (Exception e)
            {
                MessageBox.Show("The FSM type enum could not be parsed.\nException: " + e.Message + "\nData: " + e.Data, "VHDL FSM Decleration Not Recognized", MessageBoxButtons.OK, MessageBoxIcon.Exclamation);
            }

            return fsmStates;
        }

        public static List<FSM_State> vhdlParseStatesTransitions(List<FSM_State> fsmStates, string[] linesOfCode, string fsmCurrStateVar, string fsmNextStateVar)
        {
            //Find the case statement corresponding to the FSM defined by fsmCurrStateVar
            for (int i = lineOfCloseEnum; i < linesOfCode.Length; i++)
            {
                string line = linesOfCode[i].Replace("\t", String.Empty).Replace("\n", String.Empty);
                if(CaseForFSMExists(line, fsmCurrStateVar))
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
                        state.whenStmentTxt = sb.ToString();
                    }
                }
                //TODO: Find transitions to next states foreach state in fsmStates
                foreach (FSM_State state in fsmStates)
                {
                    int startIfLine = -1, endIfLine = -1;
                    int ifsCount = 0;
                    for (int i = state.whenStmentStartLine; i < state.whenStmentEndLine; i++)
                    {
                        string line = linesOfCode[i].Replace("\t", String.Empty).Replace("\n", String.Empty);
                        if (ifsCount == 0 && line.IndexOf(fsmNextStateVar) != -1)
                        {
                            state.next_states.Add("no condition", GetStateForTransition(line, fsmStates, fsmNextStateVar));
                        }
                        if (IsIfStatement(line))
                        {
                            ifsCount++;
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
                MessageBox.Show("No FSM case found based on " + fsmCurrStateVar + ".", "VHDL FSM case statement not found", MessageBoxButtons.OK, MessageBoxIcon.Exclamation);
            }

            return fsmStates;
        }

        public static FSM_State GetStateForTransition(string line, List<FSM_State> states, string fsmNextStateVar)
        {
            foreach (FSM_State state in states)
            {
                if (Regex.IsMatch(line, fsmNextStateVar+ @"(\s+|\t+)?<=(\s+|\t+)?" + state.name, RegexOptions.IgnoreCase))
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
            return Regex.IsMatch(line, @"else(\s+|\t+)([\s])", RegexOptions.IgnoreCase);
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

        public static string RemoveSpecialCharacters(string str)
        {
            return Regex.Replace(str, "[^a-zA-Z0-9_.,]+", String.Empty, RegexOptions.Compiled);
        }

        public static string RemoveLeadingMultiTabs(string str)
        {
            return Regex.Replace(str, @"^([\t]\t)", String.Empty, RegexOptions.Compiled);
        }
    }
}
