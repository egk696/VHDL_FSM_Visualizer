using GraphX.PCL.Common.Enums;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace VHDL_FSM_Visualiser.Models
{
    class GraphLayoutOptions
    {
        public bool showAllEdgesLabels { get; set; }
        public LayoutAlgorithmTypeEnum layoutAlgorithm { get; set; }
        public OverlapRemovalAlgorithmTypeEnum overlapRemovalAlgorithm { get; set; }
        public int overlapRemovalHorizontalGap { get; set; }
        public int overlapRemovalVerticalGap { get; set; }
        public EdgeRoutingAlgorithmTypeEnum edgeRoutingAlgorithm { get; set; }

        public GraphLayoutOptions()
        {
            showAllEdgesLabels = false;
            layoutAlgorithm = LayoutAlgorithmTypeEnum.FR;
            overlapRemovalAlgorithm = OverlapRemovalAlgorithmTypeEnum.FSA;
            overlapRemovalHorizontalGap = 100;
            overlapRemovalVerticalGap = 100;
            edgeRoutingAlgorithm = EdgeRoutingAlgorithmTypeEnum.SimpleER;
        }
    }
}
