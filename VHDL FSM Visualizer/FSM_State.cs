using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace VHDL_FSM_Visualizer
{
    class FSM_State
    {
        public int id;
        public string name;
        public int whenStmentStartLine = -1, whenStmentEndLine = -1;
        public string whenStmentTxt;
        public Dictionary<string, int> next_states;

        public FSM_State()
        {
        }

        public FSM_State(int id, string name)
        {
            this.id = id;
            this.name = name;
            this.next_states = new Dictionary<string, int>();
            this.whenStmentStartLine = -1;
            this.whenStmentEndLine = -1;
            this.whenStmentTxt = "";
        }

        public FSM_State(int id, string name, Dictionary<string, int> next_states)
        {
            this.id = id;
            this.name = name;
            this.next_states = next_states;
            this.whenStmentStartLine = -1;
            this.whenStmentEndLine = -1;
            this.whenStmentTxt = "";
        }
    }
}
